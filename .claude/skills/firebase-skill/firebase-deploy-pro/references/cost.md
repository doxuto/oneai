# Cost

Blaze is pay-as-you-go with no ceiling. Cost control is caps you set before traffic arrives: `maxInstances`, timeouts, per-user quotas, image size limits, and a budget alert somebody reads. Prices below are order-of-magnitude as of writing — verify against the Firebase/Google Cloud pricing pages before quoting them to anyone.

## Where the money goes (v2 functions)

| Lever | Billed as | Free tier (per month, per billing account unless noted) | Notes |
|---|---|---|---|
| Invocations | per million requests | ~2M | rarely the problem |
| CPU time | vCPU-seconds while handling a request | ~180k vCPU-s | `cpu`, `concurrency`, and how long the handler runs |
| Memory time | GiB-seconds | ~360k GiB-s | `memory` option × duration |
| Min instances | idle vCPU/GiB-seconds, 24/7 | none | `minInstances: 1` on a 1 vCPU / 512 MiB function is a fixed monthly line item; cost it before adding |
| Egress | GB leaving Google's network | small | responses to iOS count; images sent back count; calls to Gemini Developer API count as egress, Vertex AI in-region does not |
| Cloud Build | build-minutes per deploy | ~120 min/day | many small deploys add up; two codebases = two builds |
| Artifact Registry | GB stored (container images) | 0.5 GB | old images accumulate; set the cleanup policy (below) |
| Secret Manager | per active secret version + access ops | 6 versions, 10k ops | prune old versions |
| Cloud Scheduler | per job | 3 jobs | each `onSchedule` is a job |
| Cloud Tasks | per million ops | ~1M | fine |
| Cloud Logging | GiB ingested | 50 GiB / project | `debug` logs with payloads blow this |
| Firestore | reads / writes / deletes per 100k, storage, egress | 50k reads, 20k writes, 20k deletes per **day** on the default database | the usual biggest line item — see below |
| Cloud Storage | GB stored + operations + egress | 5 GB | images; set lifecycle rules |
| FCM | free | — | pushes cost nothing; the Firestore reads to find tokens do |
| Gemini | per input / output token (Flash is cheap; Pro is not) | Developer API has a free tier with limits | multimodal input (images/PDF pages) is tokenised — a 4-page scan is thousands of tokens |
| Cloud Vision | per 1,000 images per feature | ~1k units | `documentTextDetection` |

## Firestore read amplification — the trap

- An iOS snapshot listener on a query pays one read per document on first attach and one per changed document after; **reattaching** (app foreground, view re-created, TCA effect restarted) pays the full set again. Keep listeners alive across navigation (`tca-pro` long-living effects) and cap the query with `limit`.
- A trigger that reads the parent doc + writes a counter costs 1 read + 1 write per event, plus the write's own trigger if any. A trigger that writes to the path it listens on and does not guard `before == after` loops until `maxInstances` or the budget stops it.
- `collectionGroup` queries and `count()` aggregations are cheap (aggregations bill 1 read per 1,000 index entries), full collection scans in a nightly job are not — use TTL policies (free deletes) instead of a cleanup function.
- Denormalise for the read path the app shows most: one document per screen beats N reads.

## Caps — set on day one

```ts
import { setGlobalOptions } from "firebase-functions/v2";

setGlobalOptions({
  region: "asia-southeast1",
  maxInstances: 20,          // project-wide default ceiling
  timeoutSeconds: 60,
  memory: "256MiB",
  concurrency: 80,           // v2 default; many cheap requests per instance
});

// Anything that calls a paid API gets its own, lower cap
export const extractText = onCall({ maxInstances: 5, timeoutSeconds: 120, memory: "1GiB", concurrency: 4 }, handler);
export const processScan = onTaskDispatched({
  maxInstances: 3,
  rateLimits: { maxConcurrentDispatches: 3, maxDispatchesPerSecond: 2 },
  retryConfig: { maxAttempts: 3, minBackoffSeconds: 30 },
}, handler);
```

- `maxInstances` is the circuit breaker: with `concurrency: 4` and `maxInstances: 5`, at most 20 Gemini calls are in flight no matter what the client does. Requests beyond that get `resource-exhausted` / 429, which the iOS client should surface as "busy, try again" (`firebase-ios-contract`).
- `timeoutSeconds` bounds the worst case per invocation. A hung Gemini call at 540 s × 1 GiB × retries is real money.
- Retries multiply cost: `retryConfig.maxAttempts` on tasks and `retry: true` on event functions must pair with idempotency and a small `maxAttempts`.
- Per-user quota in Firestore (`users/{uid}/quotas/{yyyy-mm-dd}` with `FieldValue.increment`) inside a transaction before the paid call — the pattern in `SKILL.md`'s canonical example. One read + one write per call is far cheaper than one uncapped Gemini call.
- Input caps: reject images over N MB at the rules layer (`request.resource.size`), resize server-side with `sharp` to the smallest size the model needs, limit pages per scan.
- Log `usageMetadata` token counts per call (`monitoring.md` log-based metric) so a prompt change that doubles tokens is visible the same day.

## Budget alerts

```bash
gcloud billing budgets create \
  --billing-account BILLING_ACCOUNT_ID \
  --display-name "snaptool-prod monthly" \
  --budget-amount 200USD \
  --filter-projects projects/PROJECT_NUMBER \
  --threshold-rule percent=0.5 --threshold-rule percent=0.9 --threshold-rule percent=1.0 \
  --threshold-rule percent=1.0,basis=forecasted-spend
```

- One budget per project (dev tiny, staging small, prod real). Email goes to billing admins by default; add a Slack/PagerDuty channel via a Cloud Monitoring notification channel on the budget.
- A budget alert does **not** stop spending. The "disable billing on budget" Pub/Sub function pattern exists but takes the whole project down (Auth included). Prefer a kill switch that disables the expensive path only (`rollback-and-incidents.md`).
- Check the Firebase console → Usage and billing → "Details & settings" weekly during the first month after launch, then monthly.

## Deploy artifacts cleanup

Every deploy pushes a new container image; old ones stay in Artifact Registry and are billed per GB. The CLI can install a cleanup policy:

```bash
firebase functions:artifacts:setpolicy -P prod --days 3     # verify flag names against firebase docs for the pinned CLI version
```

If the command is unavailable in the pinned CLI, set a cleanup policy on the `gcf-artifacts` repository in the Artifact Registry console (delete versions older than N days, keep the newest 2).

## Worked estimate — a scan pipeline at 1,000 DAU

Do this arithmetic for every paid path before launch; put the sheet in `Server/docs/cost-model.md` and update the inputs monthly from real metrics.

| Input | Value |
|---|---|
| Daily active users | 1,000 |
| Scans per user per day | 2 → 2,000 scans/day → 60,000/month |
| `extractText` duration × resources | 8 s × 1 vCPU × 1 GiB (Gemini call dominates) |
| Gemini tokens per scan | ~3,000 input (one image page) + ~500 output |
| Firestore per scan | 3 reads (quota, user, scan) + 3 writes (quota, scan status ×2) + 1 trigger read |
| Push per scan | 1 FCM send, 2 token reads |

Monthly:

- Functions CPU: 60,000 × 8 s = 480,000 vCPU-s → ~300,000 billable after free tier → single-digit dollars.
- Functions memory: 480,000 GiB-s → ~120,000 billable → cents.
- Invocations: 60,000 + triggers + pushes ≈ 200,000 → free.
- Firestore: ~360,000 reads + 180,000 writes → after the daily free tier, a few dollars.
- Gemini Flash: 60,000 × 3,500 tokens ≈ 210M tokens → this is the line that matters; price it at the current Flash rate and compare Pro (an order of magnitude more). A prompt that adds a second image page doubles it.
- Storage: 60,000 × 1.5 MB = 90 GB/month new uploads → dollars per month and growing unless a lifecycle rule deletes originals.

Conclusion for this shape: Gemini tokens and Storage growth are 80 % of the bill; `maxInstances` and the per-user quota bound the worst day; the Firestore free tier hides the read cost until DAU grows 10×, so the read-per-DAU metric belongs on the dashboard now.

## Cost review checklist (monthly, and before any launch)

1. Billing report grouped by SKU for the last 30 days — top 5 lines. Anything surprising gets a ticket.
2. Every function has `maxInstances` and `timeoutSeconds`; the ones calling Gemini/Vision/FCM fan-out have lower explicit values.
3. `minInstances` > 0 only on functions with a measured cold-start complaint; the monthly cost is written next to the option in a comment.
4. Firestore reads per active user per day (Firestore usage tab ÷ DAU). Over ~500 means a listener is reattaching or a screen over-fetches.
5. No trigger writes to its own listened path without a before/after guard.
6. Gemini tokens per scan (log-based metric p50/p95) has not drifted since last month.
7. Storage lifecycle rule deletes original uploads after processing or after N days; TTL policy on `scans` for free-tier users.
8. Cloud Scheduler job count matches `onSchedule` exports (deleted functions leave orphaned jobs only if deleted outside the CLI).
9. Artifact Registry size < 1 GB; cleanup policy present.
10. Cloud Logging ingestion < free tier; no `debug` payload logging in prod.
11. Budget thresholds still match reality (raise after growth, do not silence).
12. Secret Manager: no more than 2 active versions per secret.

## Does not exist / common mistakes

- "Set a spending limit" — Blaze has no hard cap; budgets only notify.
- `maxInstances: 0` as an off switch — semantics differ between generations and the CLI may reject it; use the kill switch pattern instead.
- `minInstances: 1` on every function "for cold starts" — that is N always-on containers; put it on the one or two user-facing callables that showed measured cold-start latency, and only in prod.
- Relying on the Firestore daily free tier in a non-default database or after moving regions — the free tier applies to the default database only.
- Counting FCM as a cost — it is free; the token lookup reads are the cost.
- Assuming Gemini Developer API free-tier quotas apply in production — rate limits are low and data-use terms differ; production uses a billed key or Vertex AI.
- Using `onRequest` with `invoker: "public"` for anything but `/health` — public endpoints get scraped and every hit is billed.

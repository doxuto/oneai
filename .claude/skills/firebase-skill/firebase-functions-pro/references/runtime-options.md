# Runtime options

Every 2nd gen function is a Cloud Run service. The options object is the first argument to `onCall`/`onRequest`/`onDocument*`/`onSchedule`/…, and `setGlobalOptions` sets defaults for all of them. Options are resolved at deploy; changing them requires a redeploy of that function.

## The options

```ts
import { setGlobalOptions } from "firebase-functions/v2";

setGlobalOptions({
  region: "asia-southeast1",   // SupportedRegion | string
  memory: "256MiB",            // "128MiB" | "256MiB" | "512MiB" | "1GiB" | "2GiB" | "4GiB" | "8GiB" | "16GiB" | "32GiB"
  cpu: 1,                      // number | "gcf_gen1"; default derived from memory
  timeoutSeconds: 60,          // callable/event max 540; onRequest max 3600
  concurrency: 80,             // 1–1000; default 80; needs cpu >= 1
  minInstances: 0,             // warm instances; billed while idle
  maxInstances: 10,            // hard cap on scale-out
  serviceAccount: undefined,   // "name@project.iam.gserviceaccount.com" — default is the compute SA
  vpcConnector: undefined,
  vpcConnectorEgressSettings: undefined,
  ingressSettings: "ALLOW_ALL",   // "ALLOW_ALL" | "ALLOW_INTERNAL_ONLY" | "ALLOW_INTERNAL_AND_GCLB"
  labels: { team: "mobile" },
  secrets: [],
  preserveExternalChanges: false,  // true = leave console-edited settings alone on deploy
});
```

Per-function options override globals key by key. A function that sets `{ memory: "1GiB" }` keeps the global region and `maxInstances`.

## Region

Pick one region for everything and set it once in `setGlobalOptions`. For a Vietnam-based user base with Firestore in `asia-southeast1` (Singapore):

```ts
setGlobalOptions({ region: "asia-southeast1" });
```

Reasons:

- Callable latency is dominated by the round trip from device to function plus function to Firestore. Colocating the function with the database removes the second hop.
- Firestore triggers must deploy in a region the database supports (its own region, or `us-central1` for `nam5`, `europe-west4` for `eur3`). Storage triggers must be in the bucket's region. Colocating avoids per-trigger region overrides.
- The iOS client hard-codes the region: `Functions.functions(region: "asia-southeast1")`. A mismatch is a `not-found` at runtime, not a compile error.

Multi-region deploy (`region: ["asia-southeast1", "us-central1"]`) creates one function per region under the same name; the client still picks one. Useful only for a global product with a region-aware client. Do not do it by default.

Avoid `us-central1` as a default just because the starter template uses it — it is 200 ms+ from Southeast Asia.

## Memory and CPU

| memory | default cpu | notes |
|---|---|---|
| `128MiB` | 0.083 | Only for trivial handlers; concurrency must be 1 |
| `256MiB` | 0.167 | Default. Fine for Firestore CRUD callables; concurrency must be 1 unless cpu raised |
| `512MiB` | 0.333 → set `cpu: 1` | Callables that call an AI API or do JSON-heavy work |
| `1GiB` | 0.583 → set `cpu: 1` | Image resizing with sharp, PDF parsing |
| `2GiB`+ | 1+ | OCR, ffmpeg, large batch jobs |

Memory below `512MiB` is a fractional CPU by default, and fractional CPU forces `concurrency: 1`. In practice:

- CRUD callable, no heavy libs: `{ memory: "256MiB" }`. One request per instance, but instances are cheap and start fast.
- Anything that awaits a slow upstream (Gemini, Vision, third-party HTTP): `{ memory: "512MiB", cpu: 1, concurrency: 80 }`. The instance spends its time waiting; concurrency lets one instance serve many waiting requests, which cuts cold starts and cost.
- CPU-bound work (sharp, pdf-lib): `{ memory: "1GiB", cpu: 1, concurrency: 1–4 }`. High concurrency on CPU-bound work just makes every request slow.

Out-of-memory kills the instance mid-request and logs `Memory limit of X exceeded`. Node's heap default is tied to the container limit in the Firebase runtime; if you see OOM at 512MiB with a small heap, raise memory, do not tune `--max-old-space-size`.

## Concurrency

- v2 default is 80 when `cpu >= 1`. Each instance runs up to 80 requests on one Node event loop.
- Concurrency shares module-level state. Module-level singletons (DB clients, HTTP agents, memoised secrets) are a feature. Module-level *mutable request state* (a `let currentUid`) is a bug.
- Concurrency multiplies the effect of an unhandled rejection: one crash takes down 80 in-flight requests.
- Lower it (`concurrency: 10`) when the handler holds large buffers per request (image processing) so 80 × 50 MB does not OOM.
- Set `concurrency: 1` only for handlers that genuinely cannot share (rare) or run at fractional CPU.

## Timeout

- Callables and event functions: 1–540 s. `onRequest`: up to 3600 s.
- Set it to slightly above the p99 you expect, not the max. A runaway loop at `timeoutSeconds: 540` costs 9 minutes of instance time per request.
- The iOS SDK has its own client-side timeout (default 70 s on `HTTPSCallable.timeoutInterval`). A server timeout above 70 s is invisible to the client unless the client timeout is raised too.
- Long work (> 30 s user-facing) belongs in `onTaskDispatched` with a status document. See `firebase-ios-contract` → `references/realtime-vs-callable.md`.

Rule of thumb per function type:

| Type | `timeoutSeconds` |
|---|---|
| CRUD callable | 15–30 |
| AI callable, non-streaming | 60 |
| AI streaming callable | 120–300 |
| Firestore trigger | 60 |
| Webhook | 30 |
| Task worker | 300–540 |
| Scheduled job | 540 (and chunk the work) |

## Instances

### `maxInstances`

Set globally to a small number (`10`) and raise per function when measured. It is the single most important cost cap: a bug that re-triggers a function in a loop, or a burst from a bad client build, hits the cap instead of the credit card. Requests beyond the cap queue briefly and then fail with `unavailable` / 429 — that is what the iOS retry-with-backoff is for.

### `minInstances`

- `minInstances: 1` keeps one instance warm: no cold start for the first request after idle. Billed continuously at an idle rate (Cloud Run minimum-instance pricing), roughly the cost of a cheap VM per instance-month at 512MiB. Justified for the one or two callables the app hits on launch (`bootstrap`, `chat`), not for every function.
- Use a param to set `1` in prod and `0` in dev: `minInstances: defineInt("CHAT_MIN_INSTANCES", { default: 0 })`.
- `minInstances` does not eliminate cold starts under scale-out; it only covers the baseline.

## Service account

By default v2 functions run as the project's default compute service account, which typically has Editor. For least privilege on functions that touch nothing but Firestore and Auth, create a dedicated SA with `roles/datastore.user`, `roles/firebaseauth.admin`, and `roles/secretmanager.secretAccessor`, then `serviceAccount: "functions-api@project.iam.gserviceaccount.com"`. Do this once the project has a security review, not on day one.

## Ingress

- `ingressSettings: "ALLOW_INTERNAL_ONLY"` for task workers and functions only called by Cloud Scheduler / other functions. Combine with `invoker: "private"` on `onRequest`.
- Callables the app uses must stay `ALLOW_ALL`.

## Cost model, briefly

Billed per instance-second (CPU + memory), per request, and for egress. Consequences:

- Concurrency is the biggest lever for I/O-bound callables: 80 requests on one instance-second instead of 80 instance-seconds.
- A `512MiB, cpu: 1` instance costs about twice a `256MiB, fractional` one per second but can serve 80× the concurrent I/O-bound requests.
- `minInstances` is the only cost that accrues with zero traffic.
- `timeoutSeconds` is the ceiling on waste per request.
- Firestore reads/writes and AI tokens usually dwarf compute; log `usageMetadata` from Gemini and set per-user quotas.

Set a Cloud Billing budget alert on every project. Check `maxInstances` before every prod deploy.

## Per-function vs global

Global in `src/index.ts`:

```ts
setGlobalOptions({ region: "asia-southeast1", maxInstances: 10, memory: "256MiB", timeoutSeconds: 30 });
```

Override only where measured:

```ts
export const chat = onCall({ memory: "512MiB", cpu: 1, timeoutSeconds: 120, maxInstances: 20, secrets: [GEMINI_API_KEY] }, ...);
export const processScan = onTaskDispatched({ memory: "1GiB", cpu: 1, concurrency: 4, timeoutSeconds: 540, maxInstances: 5, retryConfig: { maxAttempts: 3 } }, ...);
```

Do not restate the global region on each function. Do restate `maxInstances` on anything that fans out or costs money per call, so the cap is visible next to the code that spends.

## Does not exist / common mistakes

- `.runWith({ memory: "1GB" })` — v1. v2 uses the options object and `"1GiB"` (binary suffix).
- `memory: "1GB"` / `memory: 1024` — invalid in v2; use the string union with `MiB`/`GiB`.
- `functions.region("asia-southeast1").https.onCall` — v1 chaining. v2 is `onCall({ region }, ...)` or `setGlobalOptions`.
- `concurrency: 80` with `memory: "256MiB"` and no `cpu: 1` — deploy error (concurrency > 1 requires ≥ 1 CPU).
- `timeoutSeconds: 3600` on a callable — max 540; the CLI rejects it.
- Expecting `setGlobalOptions` in a file other than the entry point to apply — it must run before function modules are evaluated.
- Changing `region` on an existing function — that is a delete + create in a new region with a new URL; the client must be updated in step.

# Cost and limits

An AI feature is a metered API behind a mobile app with unknown users. Every function that touches a model has: a per-user quota, an input cap, a model tier, a timeout shorter than the function's, an instance cap, and a log line with token counts. Missing any one of these is a finding.

## Central config

```ts
// functions/src/ai/config.ts
export const AI = {
  backend: "developer-api" as "developer-api" | "vertex",   // document the choice; affects data-use terms
  models: {
    classify: "gemini-2.5-flash-lite",
    extract:  "gemini-2.5-flash",
    summarize: "gemini-2.5-flash",
    chat:     "gemini-2.5-flash",
    hard:     "gemini-2.5-pro",         // used only by features whose eval failed on flash
  },
  limits: {
    dailyCallsPerUser: 50,
    dailyPagesPerUser: 40,
    maxInputChars: 30_000,
    maxPagesPerScan: 20,
    maxImageEdgePx: 1600,
    maxOutputTokens: { classify: 256, extract: 8192, summarize: 1024, chat: 1024 },
  },
} as const;
```

Check the current model list before changing names; keep them here and nowhere else.

## Per-user daily quota document

`users/{uid}/quota/{yyyy-mm-dd}` with counters per unit. Increment in a transaction *before* the model call; on failure of the call, do not decrement (the attempt cost tokens). Plan-based limits come from the user document's `plan` (set server-side only).

```ts
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

const db = getFirestore();
const PLAN_LIMITS: Record<string, { calls: number; pages: number }> = {
  free: { calls: 20, pages: 10 },
  pro:  { calls: 300, pages: 200 },
};

export async function consumeQuota(uid: string, units: { calls?: number; pages?: number }): Promise<void> {
  const day = new Date().toISOString().slice(0, 10);                      // UTC day; simple and consistent
  const quotaRef = db.doc(`users/${uid}/quota/${day}`);
  const userRef = db.doc(`users/${uid}`);
  await db.runTransaction(async (tx) => {
    const [quota, user] = await Promise.all([tx.get(quotaRef), tx.get(userRef)]);   // reads first
    const plan = (user.get("plan") as string | undefined) ?? "free";
    const limit = PLAN_LIMITS[plan] ?? PLAN_LIMITS.free;
    const calls = ((quota.get("calls") as number | undefined) ?? 0) + (units.calls ?? 0);
    const pages = ((quota.get("pages") as number | undefined) ?? 0) + (units.pages ?? 0);
    if (calls > limit.calls || pages > limit.pages) {
      throw new HttpsError("resource-exhausted", "Daily AI limit reached", { plan, limit, resetsAt: `${day}T23:59:59Z` });
    }
    tx.set(quotaRef, {
      calls: FieldValue.increment(units.calls ?? 0),
      pages: FieldValue.increment(units.pages ?? 0),
      updatedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(Date.now() + 7 * 86_400_000),       // TTL policy on quota.expiresAt
    }, { merge: true });
  });
}
```

Rules: `allow read: if isOwner(uid); allow write: if false;` so the app can show "12 / 20 today" and the user cannot reset it. The iOS side maps `.resourceExhausted` + `details.resetsAt` to a paywall or a countdown (`tca-pro` navigation).

For task-queue workers (document pipeline), consume `pages` in the enqueue step (Storage trigger) so the user sees `failed/quota` immediately instead of a queued scan that later fails.

## Input caps

- Text: `slice(0, AI.limits.maxInputChars)` and tell the model the text may be truncated. 30k characters ≈ 8–10k tokens for Vietnamese/English.
- Pages: reject `pageCount > maxPagesPerScan` in rules and in the trigger.
- Chat history: keep the last N turns and a running summary; never send the whole conversation. Store the summary on the conversation document and refresh it every ~10 turns with a flash-lite call.
- Pre-flight with `ai.models.countTokens` only when the input is close to the model's context limit; for normal caps, character counting is enough and free.

## Image downscale

Gemini bills images by tiles (roughly 258 tokens per 768 px tile on 2.5 models — check the current pricing page), so a 4000 px photo costs many times a 1600 px one and reads no better for documents.

```ts
import sharp from "sharp";
export async function normalizeImage(raw: Buffer, maxEdge = 1600): Promise<Buffer> {
  return sharp(raw, { failOn: "none" })
    .rotate()                                                       // apply EXIF orientation (iOS photos)
    .resize({ width: maxEdge, height: maxEdge, fit: "inside", withoutEnlargement: true })
    .jpeg({ quality: 80, mozjpeg: true })
    .toBuffer();
}
```

`sharp` needs `memory: "512MiB"` or more and adds ~1 s cold start; keep it out of callables that do not process images (separate codebase or lazy `await import("sharp")`). HEIC input: convert on the device before upload; `sharp` HEIC support depends on the libvips build.

## Model tiering

| Tier | Model | Use for | Notes |
|---|---|---|---|
| lite | `gemini-2.5-flash-lite` | classification, language detection, short rewrites, chat-history summaries | cheapest; good with enums |
| default | `gemini-2.5-flash` | OCR + extraction, summaries, Q&A, translation | `thinkingConfig.thinkingBudget: 0` for extraction to cut latency and cost; keep thinking for reasoning-heavy Q&A |
| pro | `gemini-2.5-pro` | multi-page reconciliation, ambiguous layouts, long reasoning | 5–10× the cost; only where the golden set shows flash failing |

Escalation pattern: run flash; if the validated result has `unreadableFields.length > 3` or confidence below threshold, re-run on pro once and record `model` on the result. Most documents never hit pro.

Check the current model list and pricing before pinning any name.

## Context caching

For a large fixed prefix (long system instruction with few-shot examples, a product manual for Q&A, a 50-page PDF the user asks several questions about), cache it and reference it:

```ts
const cache = await ai.caches.create({
  model: AI.models.chat,
  config: { contents: [{ role: "user", parts: [pdfPart] }], systemInstruction: MANUAL_SYSTEM, ttl: "1800s", displayName: `scan-${scanId}` },
});
await db.doc(`users/${uid}/scans/${scanId}`).update({ cacheName: cache.name, cacheExpiresAt: Timestamp.fromMillis(Date.now() + 1800_000) });
// later calls:
await ai.models.generateContent({ model: AI.models.chat, contents: question, config: { cachedContent: cache.name } });
```

Caches have a minimum token size (thousands of tokens — check the current minimum per model), are billed per hour of storage, and are only worth it when the prefix is reused several times within the TTL. `usageMetadata.cachedContentTokenCount` shows the discount; log it.

## Timeouts, memory, instances

| Function | `timeoutSeconds` | `memory` | `maxInstances` | model `abortSignal` |
|---|---|---|---|---|
| classify callable | 30 | 256MiB | 20 | 20 s |
| summarize / translate callable | 60 | 256MiB | 20 | 45 s |
| chat streaming callable | 120 | 256MiB | 30 | 100 s |
| scan worker (task) | 540 | 1GiB | 5 (+ `rateLimits.maxConcurrentDispatches`) | 300 s |

- The model call's `abortSignal` is always shorter than `timeoutSeconds` so the client receives `deadline-exceeded` with a message instead of a dropped connection.
- `maxInstances` caps the blast radius of a bug or an abusive client: 20 instances × 80 concurrency is already a lot of Gemini QPS. Set `concurrency` lower (10–20) for AI callables — each request holds an open model stream, and high concurrency on a 256 MiB instance risks memory pressure.
- `minInstances: 1` only for the chat callable if cold-start latency is a product complaint; it costs idle time continuously.
- `cpu: 1` is enough; AI functions are I/O-bound.

## Logging tokens

One structured line per model call, same keys everywhere, so a Logs Explorer query or a log-based metric can sum them:

```ts
logger.info("gemini", {
  feature, uid, model, promptVersion,
  promptTokens: usage?.promptTokenCount ?? 0,
  outputTokens: usage?.candidatesTokenCount ?? 0,
  thoughtTokens: usage?.thoughtsTokenCount ?? 0,
  cachedTokens: usage?.cachedContentTokenCount ?? 0,
  totalTokens: usage?.totalTokenCount ?? 0,
  latencyMs: Date.now() - startedAt,
});
```

Create a log-based metric (`jsonPayload.totalTokens`, summed, labelled by `jsonPayload.feature` and `jsonPayload.model`) and alert when the daily sum exceeds the expected envelope. Persist per-user monthly totals only if the product needs a usage screen; `quota` counts are enough for enforcement.

## Budget alerts and kill switch

- Cloud Billing budget on the project with alerts at 50/90/100 % (email + Pub/Sub). Gemini Developer API usage bills to the project the key belongs to — keep it the same project so one budget covers it.
- A `defineString("AI_ENABLED")` param (`.env.<project>`) or a `config/ai` Firestore document with `{ enabled: true }` read at the top of every AI function → throw `unavailable` when off. Flipping a document is faster than redeploying when a budget alert fires at 3 a.m.
- Per-feature: `AI_MAX_DAILY_CALLS` params let you lower limits without a code change.

## Does not exist / common mistakes

- Quota check after the model call — the call already cost money; check first.
- Quota counters on the user document — one hot document with every feature writing to it; use the dated subdocument.
- `FieldValue.increment` outside a transaction as the check — increments cannot enforce a ceiling; the transaction reads then writes.
- Sending the full-resolution image "for accuracy" — tokens scale with tiles, not accuracy, for documents.
- `timeoutSeconds: 540` on a callable "to be safe" — the client's default 70 s timeout fires first; align both and keep interactive calls short.
- `maxInstances` unset on AI functions — one runaway client loop can spend the monthly budget in an hour.
- Trusting `thinkingBudget: 0` on `gemini-2.5-pro` — Pro cannot disable thinking; budget it instead.
- Context caching for a 500-token system prompt — below the minimum and not worth the storage cost.

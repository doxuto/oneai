# Rate limiting and abuse protection

Targets firebase-functions 6.x, firebase-admin 13.x. Firebase has no built-in per-user rate limiter for callables; you build it from App Check, Auth, a Firestore quota document, and instance caps.

## The layers

| Layer | Question it answers | Stops | Does not stop |
|---|---|---|---|
| App Check (`enforceAppCheck`) | Is this my app? | curl, scripts, leaked API keys | a real user in the real app |
| Auth (`request.auth`) | Who is this? | anonymous-network abuse, attribution gaps | a signed-in user looping a call |
| Per-user quota doc | How much has *this uid* done in this window? | one user burning your Gemini bill | 10 000 fresh anonymous accounts |
| Anonymous restrictions | Is this identity cheap to create? | account farming for free quota | nothing else |
| Per-IP limiter (`onRequest` only) | Where from? | a single host hammering a webhook | distributed sources |
| `maxInstances` / `timeoutSeconds` / `concurrency` | How much can this cost me? | runaway bills, retry storms | nothing at the request level |
| Cloud Billing budget alert | Did all of the above fail? | surprises at month end | the spend itself (alerts do not cap) |

Every expensive callable — anything that calls Gemini/Vision, sends push to many tokens, writes more than a handful of documents, or generates signed URLs — needs all of the first four plus `maxInstances`.

## Per-user quota document

Shape: one doc per user per feature, `users/{uid}/quota/{key}`, written **only by the Admin SDK** (rules: owner read, no write). Fixed window (reset at window start) is enough; sliding windows need more reads than they are worth.

```ts
// functions/src/lib/quota.ts
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/logger";

export interface QuotaDoc {
  count: number;
  windowStart: Timestamp;
  updatedAt: Timestamp;
}

/**
 * Consume one unit of `key` for `uid`. Throws resource-exhausted when over `limit` per `windowSeconds`.
 * Runs in a transaction so concurrent calls cannot both pass at count == limit - 1.
 */
export async function consumeQuota(
  uid: string,
  key: string,
  limit: number,
  windowSeconds = 24 * 3600,
  cost = 1,
): Promise<{ remaining: number; resetsAt: Timestamp }> {
  const db = getFirestore();
  const ref = db.doc(`users/${uid}/quota/${key}`);
  const now = Timestamp.now();

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);                         // read first, always
    const data = snap.exists ? (snap.data() as QuotaDoc) : undefined;
    const windowExpired = !data || now.seconds - data.windowStart.seconds >= windowSeconds;
    const windowStart = windowExpired ? now : data!.windowStart;
    const current = windowExpired ? 0 : data!.count;
    const resetsAt = Timestamp.fromMillis(windowStart.toMillis() + windowSeconds * 1000);

    if (current + cost > limit) {
      logger.warn("quota exceeded", { uid, key, current, limit });
      throw new HttpsError("resource-exhausted", "Daily limit reached.", {
        key, limit, resetsAt: resetsAt.toDate().toISOString(),   // ISO, never a Timestamp
      });
    }
    if (windowExpired) {
      tx.set(ref, { count: cost, windowStart, updatedAt: FieldValue.serverTimestamp() });
    } else {
      tx.update(ref, { count: FieldValue.increment(cost), updatedAt: FieldValue.serverTimestamp() });
    }
    return { remaining: limit - current - cost, resetsAt };
  });
}
```

Usage in a callable — **check quota before doing the expensive work, and after auth**:

```ts
export const ocrScan = onCall({ enforceAppCheck: true, maxInstances: 20, timeoutSeconds: 120 }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  const uid = request.auth.uid;
  const isAnon = request.auth.token.firebase.sign_in_provider === "anonymous";
  const plan = request.auth.token.plan === "pro" ? "pro" : "free";
  const limit = isAnon ? 3 : plan === "pro" ? 500 : 20;
  const { remaining } = await consumeQuota(uid, "ocr", limit);
  // ... expensive work ...
  return { remaining };
});
```

Notes:

- `HttpsError` thrown inside `runTransaction` propagates unchanged — the transaction is not retried for an `HttpsError` because it is not a contention error. Confirm by testing; the Admin SDK retries only on `ABORTED`-style commit failures.
- Hot-spot limit: 1 write/sec sustained per document. A per-user doc is fine; a single global `quota/all` doc is not — shard it (`quota/all_{0..9}` picked by hash) or do not build a global limiter in Firestore.
- Refunds: if the expensive call fails for a server-side reason, decrement (`FieldValue.increment(-cost)`) so the user is not charged for your outage. Do not refund on client-side cancellations.
- Expose `remaining` and `resetsAt` (ISO) to the iOS app so it can show "3 scans left today" instead of surfacing `resourceExhausted` as an error. The TCA feature maps `FunctionsErrorCode.resourceExhausted` + `details["resetsAt"]` into an alert state.
- Plan limits come from the `plan` claim, not from a document the client can write.

## Long-window and abuse counters

For "max 5 accounts per device" or "max 50 shares per month" reuse the same doc with a different `windowSeconds`. For lifetime counters (`totalScans`) use `FieldValue.increment` on the user doc outside a transaction — no limit check, just accounting.

Suspicious-activity flags: when quota is exceeded N times in a window, set `users/{uid}.flags.abuse = true` and have rules/callables treat flagged users as read-only until reviewed. Keep the flag server-only (rules `hasAny(['flags'])` in the update deny list).

## Anonymous users

Anonymous sign-in is free and unlimited from the client, so per-uid quota is trivially bypassed by signing out and in. Mitigations, in order of usefulness:

1. Give anonymous users a **tiny** quota (3/day) and gate anything expensive behind linking an account (`failed-precondition` with `reason: "link-required"`).
2. Enforce App Check on Authentication in the console so anonymous accounts can only be minted by the real app.
3. Track `X-Firebase-AppCheck` `appId` + `request.rawRequest.ip` in logs for correlation; do not block on IP alone (carrier NAT in Vietnam puts thousands of users behind one IP).
4. Enable anonymous auto-cleanup (console → Authentication → Settings) and a scheduled job that deletes anonymous users' data after 30 days.

## Per-IP limiting for `onRequest`

Only for endpoints without Firebase identity (webhooks, public health checks). Cloud Functions v2 runs on Cloud Run; the client IP is in `req.ip` (Express trusts the Google front end) — verify `req.ip` vs `x-forwarded-for` against current docs for your setup.

```ts
import { onRequest } from "firebase-functions/v2/https";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

const WINDOW_SECONDS = 60;
const LIMIT = 30;

export const publicPing = onRequest({ maxInstances: 3, invoker: "public" }, async (req, res) => {
  const ip = req.ip ?? "unknown";
  const bucket = Math.floor(Date.now() / 1000 / WINDOW_SECONDS);
  const ref = getFirestore().doc(`_ratelimit/${ip.replace(/[:.]/g, "_")}_${bucket}`);
  const snap = await ref.get();
  if ((snap.data()?.count ?? 0) >= LIMIT) { res.status(429).set("Retry-After", String(WINDOW_SECONDS)).send("Too many requests"); return; }
  await ref.set({ count: FieldValue.increment(1), expiresAt: Timestamp.fromMillis((bucket + 2) * WINDOW_SECONDS * 1000) }, { merge: true });
  res.status(200).send("pong");
});
```

Put a TTL policy on `_ratelimit.expiresAt` so the docs vanish. This is best-effort (read-then-write race), acceptable for a public endpoint; for anything that matters use a callable with identity. For real edge rate limiting put Cloud Armor in front of Cloud Run (outside the Firebase CLI; mention, do not design here).

## Instance and time caps

```ts
setGlobalOptions({ region: "asia-southeast1", maxInstances: 10, timeoutSeconds: 60 });
export const ocrScan = onCall({ maxInstances: 20, timeoutSeconds: 120, memory: "1GiB", concurrency: 10 }, ...);
export const nightlyCleanup = onSchedule({ schedule: "every day 03:00", timeZone: "Asia/Ho_Chi_Minh", maxInstances: 1, retryCount: 1 }, ...);
```

- `maxInstances` bounds cost per function; `concurrency` (default 80 on v2) × `maxInstances` bounds simultaneous requests. A Gemini-calling function with `concurrency: 80` and `maxInstances: 100` can open 8 000 model calls at once — set concurrency low for expensive handlers.
- `timeoutSeconds` bounds one request; a hung upstream (model API) otherwise bills the full 540 s.
- Task queue workers get `rateLimits: { maxConcurrentDispatches, maxDispatchesPerSecond }` and `retryConfig` — the right place to throttle fan-out (see `firestore-data-pro` → `references/task-queues.md`).
- Triggers: a Firestore trigger with no `maxInstances` and a bug that writes back to the same doc is an infinite, parallel, billed loop. Cap it and guard before/after.

## Cost-attack awareness

Things an attacker with a valid app + account can do that App Check will not stop:

- Call the OCR/LLM callable in a loop → quota doc + `maxInstances` + `concurrency`.
- Upload 10 MiB images 1 000 times → Storage rules size cap + quota on the *trigger* (count uploads per user per day in `onObjectFinalized`, delete overage, flag).
- Subscribe listeners to large collections → `request.query.limit` in rules, paginate, never expose a collection with unbounded growth to a listener.
- Enqueue tasks via a callable → quota the callable, not just the worker.
- Trigger push fan-out (share with 500 users) → cap recipients in validation (`z.array().max(20)`), quota shares.
- Repeatedly request signed URLs → quota + short expiry.
- Create anonymous accounts → see above.

Detection: Cloud Monitoring alerts on function invocation count and error rate per function; a Cloud Billing budget with alerts at 50/90/100 %. Neither stops spend — `maxInstances` does.

## Does not exist / common mistakes

- `rateLimit` / `rateLimits` as an option on `onCall` or `onRequest` — does not exist. `rateLimits` is a task-queue option on `onTaskDispatched` only.
- Rate limiting inside Firestore rules by counting documents — rules cannot count; `get()` is limited to 10 reads per request.
- A quota check that reads, compares, then writes outside a transaction — two concurrent requests both pass at `limit - 1`. Use `runTransaction`.
- Charging quota after the expensive work — a failing call still costs you; consume first, refund on server-side failure.
- Global counters in a single document (`stats/global.requests`) — 1 write/sec hot-spot; shard or use Cloud Monitoring metrics instead.
- Blocking by IP for authenticated iOS traffic — mobile carriers NAT huge user populations; you will block real users.
- Relying on a budget alert to stop spending — it only emails. Cap instances.

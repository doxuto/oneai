# Idempotency

Targets firebase-functions 6.x, firebase-admin 13.x. Every trigger, task, scheduled job, and mutating callable in this bundle must be safe to run twice with the same input.

## Why "exactly once" is an illusion

- Firestore triggers and storage triggers are delivered **at least once** by Eventarc. A handler that timed out, crashed, or returned a rejected promise is redelivered (with `retry: true`) or may be redelivered anyway in rare infrastructure cases.
- Cloud Tasks retries a task until the handler returns 2xx or `maxAttempts` is reached; a worker that did the work and then crashed before responding runs again.
- Cloud Scheduler with `retryCount > 0` re-runs a failed job; a job can also be run manually or fire twice around a deploy.
- The iOS app retries callables on network failure (`URLSession` timeouts, user taps twice, TCA effect re-run after app relaunch). The server saw the first request; the client did not see the response.
- Even a single successful invocation can perform its side effect and then fail on the last write.

So the question is never "how do I prevent duplicates" but "what does the second run do". The answer must be: nothing, or the same thing.

## Strategies, cheapest first

1. **Idempotent by construction** — the write does not depend on how many times it runs: `set` with a full document, `set` with `{ merge: true }`, `update` to a computed value, `arrayUnion`, `delete`. Prefer these. `increment(1)` is **not** idempotent — it is the main reason ledgers exist.
2. **Deterministic document id** — derive the id from the input (`users/{uid}/inbox/{shareId}`, `users/{uid}/devices/{installationId}`, `thumbnails/{objectGeneration}`) and use `set`/`create`. Second run overwrites with identical data or fails with `ALREADY_EXISTS`.
3. **Conditional write** — compare stored state before writing (`if (after.wordCount === computed) return`), or use `update` with a precondition: `ref.update(data, { lastUpdateTime: snap.updateTime })` fails with `FAILED_PRECONDITION` if the doc changed since you read it.
4. **Event ledger** — record `event.id` (or task id, or client dedupe key) with `ref.create` before doing non-idempotent work (`increment`, push send, external API call, enqueue). Second run sees `ALREADY_EXISTS` and returns.
5. **Status machine** — the document carries `status` and the handler only proceeds from the expected state, moving it forward in a transaction (`queued → processing → done`). Redelivery finds `processing`/`done` and exits.

Combine 4 and 5 for pipelines with external side effects.

## Event ledger with `ref.create`

```ts
// functions/src/lib/ledger.ts
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";

const db = getFirestore();
const LEDGER_TTL_DAYS = 7;

/**
 * Claim an idempotency key. Returns true if this caller is the first; false if already claimed.
 * Put a TTL policy on `events.expiresAt` so the collection stays small.
 */
export async function claim(key: string, meta: Record<string, unknown> = {}): Promise<boolean> {
  const ref = db.doc(`events/${sanitize(key)}`);
  try {
    await ref.create({ ...meta, claimedAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(Date.now() + LEDGER_TTL_DAYS * 86_400_000) });
    return true;
  } catch (err) {
    if ((err as { code?: number }).code === 6) return false;   // ALREADY_EXISTS
    throw err;                                                  // transient — let the platform retry
  }
}

/** Release a claim when the work failed for a transient reason so the retry can run. */
export async function release(key: string): Promise<void> {
  await db.doc(`events/${sanitize(key)}`).delete();
}

function sanitize(key: string): string {
  return key.replace(/\//g, "_").slice(0, 1400);   // doc ids cannot contain "/"; keep under the 1500-byte path limit
}
```

Usage in a trigger with an external side effect:

```ts
export const onOrderPaid = onDocumentUpdated({ document: "orders/{orderId}", region: "asia-southeast1", maxInstances: 5, retry: true }, async (event) => {
  if (!event.data) return;
  const before = event.data.before.get("status"), after = event.data.after.get("status");
  if (!(before !== "paid" && after === "paid")) return;                // transition guard (strategy 3)
  const key = `onOrderPaid:${event.id}`;
  if (!(await claim(key, { orderId: event.params.orderId }))) return;   // ledger (strategy 4)
  try {
    await sendReceiptEmail(event.data.after.data());                    // non-idempotent side effect
    await event.data.after.ref.update({ receiptSentAt: FieldValue.serverTimestamp() });
  } catch (err) {
    await release(key);                                                  // allow the retry to try again
    throw err;
  }
});
```

Choosing the key:

- Triggers: `event.id` — stable across redeliveries of the same event. Prefix with the function name so two functions on the same event do not collide.
- Storage triggers: `event.id`, or `${bucket}/${name}#${generation}` when the same object can be re-finalised (overwrite creates a new generation).
- Tasks: a key inside the payload that **you** generate at enqueue time (`taskId: uuid` or the deterministic work id like `scanId:page-1`). Do not rely on Cloud Tasks task names unless you set them yourself (`enqueue` options do not expose a task name in the Firebase SDK — verify against firebase docs).
- Scheduled jobs: `${jobName}:${event.scheduleTime}` (the scheduled time, not `Date.now()`).
- Callables: the client-generated dedupe key (below).

Ledger window: TTL of a few days is enough for platform retries (Eventarc ≤ 7 days with `retry: true`; Cloud Tasks per `retryConfig`); size it to the longest retry horizon.

## Dedupe keys for callables from iOS

The iOS app generates a UUID per logical operation and sends it with the request. The same UUID retried yields the same result without repeating the work.

```swift
// iOS — the id is created once per user intent, not per attempt
struct CreateNoteRequest: Codable { let requestId: String; let title: String }
let request = CreateNoteRequest(requestId: uuid().uuidString, title: title)   // `uuid` from @Dependency(\.uuid) in TCA
let response = try await createNote(request)                                 // safe to retry with the same `request`
```

```ts
const CreateNote = z.object({ requestId: z.string().uuid(), title: z.string().min(1).max(200) });

export const createNote = onCall({ region: "asia-southeast1", enforceAppCheck: true }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  const uid = request.auth.uid;
  const input = CreateNote.parse(request.data);
  // Deterministic id from the dedupe key → strategy 2, no ledger needed.
  const noteRef = db.doc(`users/${uid}/notes/${input.requestId}`);
  try {
    await noteRef.create({ ownerId: uid, title: input.title, tags: [], shareCount: 0, isDeleted: false, schemaVersion: 2,
      createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
  } catch (err) {
    if ((err as { code?: number }).code !== 6) throw err;   // ALREADY_EXISTS → the first attempt succeeded
  }
  return { id: noteRef.id };                                 // identical response on retry
});
```

When the operation's result cannot be reconstructed from a deterministic doc (e.g. it returned a generated summary), store the response in the ledger doc (`events/{uid}:{requestId}` → `{ response }`) and return it on the duplicate. Scope ledger keys by `uid` so one user cannot replay another's key.

Do not accept a dedupe key without auth scoping, and do not let the client choose ids in top-level collections where collisions matter.

## Retries on tasks and schedules

- Tasks: the worker is idempotent on the payload's own id; the enqueuing side is idempotent by writing a status doc first (`status: "queued", taskEnqueuedAt`) and skipping enqueue if it is already set — or by tolerating duplicate tasks because the worker is idempotent. Prefer the latter; it is simpler.
- A worker that reads `status === "done"` returns immediately (2xx) so Cloud Tasks stops retrying.
- A worker that fails permanently (invalid input) must **not** throw — log, mark the doc `failed` with a client-safe error, return normally. Throwing means retries until `maxAttempts`.
- Scheduled jobs: claim `${name}:${event.scheduleTime}` in the ledger; process with cursors so a retry resumes rather than restarts (`scheduled-jobs.md`).

## Non-idempotent side effects checklist

Anything on this list needs a ledger or a status transition guard before it: `FieldValue.increment`, `arrayUnion` of a non-unique value, FCM `send`, email/SMS, third-party POST (RevenueCat, Stripe, webhook), `taskQueue().enqueue` of work that is itself not idempotent, Gemini/Vision calls (cost), creating docs with auto ids (`collection.doc()` without a deterministic id), signed URL generation (harmless but rate-limited), `setCustomUserClaims` with computed values (safe if pure).

## Testing idempotency

For every trigger/task/callable test: invoke twice with the same event/payload, assert the final state equals the single-invocation state and that the external mock was called once. `firebase-functions-test` wrap + a fake `sendReceiptEmail`; see `firebase-testing-pro`.

## Does not exist / common mistakes

- Relying on `event.id` being different on redelivery — it is the same; that is the point.
- Using `Date.now()` or a fresh `uuid()` inside the handler as the ledger key — every run gets a new key; nothing is deduplicated.
- Checking `exists` with `get` then `set` — a race under concurrent redelivery; `create` is the atomic check-and-set.
- Putting the ledger write **after** the side effect — a crash in between repeats the side effect.
- Ledger without TTL — grows forever; set `expiresAt` and a TTL policy.
- Trusting client-sent `requestId` as a global key — scope by uid.
- `retry: true` on a non-idempotent trigger — turns a rare duplicate into a guaranteed one.
- Assuming a transaction makes a handler idempotent — it makes one run atomic; a second run still re-applies `increment`.

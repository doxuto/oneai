# Transactions, batches, and BulkWriter

Targets firebase-admin 13.x (`firebase-admin/firestore`, which re-exports `@google-cloud/firestore`).

## Which one

| Need | Use |
|---|---|
| Read-then-write that must be consistent (spend a credit, claim a username, conditional state change, counter that depends on current value) | `db.runTransaction` |
| Several writes that must all succeed or all fail, no reads needed (create note + bump counter with `increment`, move a doc) | `db.batch()` (≤ 500 ops) |
| Hundreds to millions of independent writes (backfill, fan-out, bulk delete) | `db.bulkWriter()` |
| A single write | `ref.set/update/delete/create` — do not wrap one write in a batch |
| Increment without reading | `FieldValue.increment` in a plain `update` — atomic on the server, no transaction needed |
| Create only if absent | `ref.create(data)` — throws `ALREADY_EXISTS` (`code === 6`), no transaction needed |

## `runTransaction`

```ts
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

const db = getFirestore();

export async function spendCredit(uid: string, cost: number): Promise<number> {
  const userRef = db.doc(`users/${uid}`);
  return db.runTransaction(
    async (tx) => {
      // 1. All reads first.
      const user = await tx.get(userRef);
      if (!user.exists) throw new HttpsError("not-found", "User not found.");
      const credits = (user.get("credits") as number | undefined) ?? 0;
      // 2. Decide.
      if (credits < cost) throw new HttpsError("failed-precondition", "Not enough credits.", { credits });
      // 3. Writes last. No await on anything that is not `tx.*` after this point.
      tx.update(userRef, { credits: FieldValue.increment(-cost), updatedAt: FieldValue.serverTimestamp() });
      tx.set(db.collection(`users/${uid}/ledger`).doc(), { delta: -cost, at: FieldValue.serverTimestamp() });
      return credits - cost;
    },
    { maxAttempts: 5 },   // default 5; readOnly: true for consistent multi-doc reads without writes
  );
}
```

Rules the SDK enforces or that bite you if you break them:

- **Reads before writes.** `tx.get` after any `tx.set/update/delete` throws `Firestore transactions require all reads to be executed before all writes`. Also `tx.get` on a query (`tx.get(collection.where(...))`) is allowed and locks the query's result set — keep it small.
- **Retry on contention.** If a document read in the transaction changed before commit, the whole callback re-runs (up to `maxAttempts`). Everything inside must be **pure with respect to side effects**: no push sends, no enqueues, no logging that you cannot see twice, no mutation of outer variables you read later. Do side effects after `runTransaction` resolves.
- **`HttpsError` thrown inside** is not a contention error; the SDK rethrows it without retry (verify with a test in your version — the Admin SDK retries on `ABORTED`-class commit errors, not on user exceptions). Throwing is the way to abort with a client-facing reason.
- **No non-Firestore awaits inside.** A `fetch` inside the callback runs on every retry and stretches the lock window; the transaction's own timeout is 270 s but contention rises with duration. Do external calls before (to compute inputs) or after.
- **Keep it small.** Under ~10 documents. Transactions are optimistic on the server side (no long locks) but each retry costs the reads again.
- **Do not read outside then write inside.** A `ref.get()` before `runTransaction` followed by a conditional `tx.update` is a race; the read must be `tx.get`.
- **The return value** of the callback is the return of `runTransaction`. Return plain data; do not return snapshots that you then mutate.
- **`readOnly: true`** gives a consistent snapshot across several reads (e.g. export) without write locks: `db.runTransaction(async (tx) => { … }, { readOnly: true })`.

Client-side (iOS) transactions exist (`Firestore.firestore().runTransaction`), but rules apply and the client can be offline; anything that touches money or quota is a callable + server transaction.

## Batches

```ts
const batch = db.batch();
const noteRef = db.collection(`users/${uid}/notes`).doc();          // pre-generated id
batch.set(noteRef, { title, ownerId: uid, schemaVersion: 2, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
batch.update(db.doc(`users/${uid}`), { noteCount: FieldValue.increment(1) });
batch.set(db.doc(`users/${uid}/inbox/${noteRef.id}`), { … }, { merge: true });
await batch.commit();                                              // atomic: all or nothing
```

- Max **500 operations** per batch. `FieldValue` transforms (`serverTimestamp`, `increment`, `arrayUnion`) no longer count as extra operations in current Firestore, but stay well under 500 anyway.
- No reads. If a write depends on current state, that is a transaction.
- A batch is atomic but **not isolated from concurrent writers** — two batches incrementing with `increment` both apply correctly; two batches doing `set` of a computed value race.
- Chunk loops: `for (const chunk of chunks(refs, 400)) { const b = db.batch(); …; await b.commit(); }` — or use BulkWriter, which does the chunking and retries for you.
- A batch fires every trigger for every doc it touches, in no particular order.

## BulkWriter

For large volumes of independent writes. Not atomic; each write succeeds or fails on its own, with automatic retry and rate ramp-up (500/50/5 rule) built in.

```ts
import { getFirestore, BulkWriterError } from "firebase-admin/firestore";
import { logger } from "firebase-functions/logger";

const db = getFirestore();
const bw = db.bulkWriter({ throttling: true });   // default true: ramps up per Firestore best practice

bw.onWriteError((err: BulkWriterError) => {
  // Retry transient errors a few times; give up on others.
  const retry = err.failedAttempts < 3 && (err.code === 14 /* UNAVAILABLE */ || err.code === 4 /* DEADLINE_EXCEEDED */ || err.code === 10 /* ABORTED */);
  if (!retry) logger.error("bulk write failed", { path: err.documentRef.path, code: err.code, attempts: err.failedAttempts });
  return retry;
});
bw.onWriteResult((ref, result) => { /* result.writeTime */ });

const snap = await db.collection("users").select().get();           // ids only — cheaper
for (const doc of snap.docs) {
  bw.update(doc.ref, { schemaVersion: 2 });                        // returns a promise per write; do not await each
}
await bw.close();                                                  // flushes and waits for all pending writes; writer is unusable afterwards
// bw.flush() waits without closing, for streaming loops
```

Facts:

- Operations: `create`, `set`, `update`, `delete`; each returns `Promise<WriteResult>` that rejects on final failure (after `onWriteError` returns false). Attach `.catch` per write or rely on `onWriteError` for logging; an unhandled rejection from a single write crashes the function.
- `close()` returns when everything is flushed. Always call it (or `flush()`) before the function returns, or writes are lost.
- `recursiveDelete(ref, bulkWriter?)` uses a BulkWriter internally; pass your own to customise error handling.
- Memory: BulkWriter buffers pending writes; for millions of docs stream the query with `.stream()` and `await bw.flush()` every ~10 k writes.
- It fires triggers for every write, like everything else.

## Contention patterns

- **Same doc from many callers** (a popular note's `viewCount`): don't transact — `increment` in a plain update is atomic and cheap. If > 1 write/sec, shard.
- **Same doc, must read current value** (`credits`, `inventory`): transaction; expect retries under load; keep the doc small so retries are cheap; consider a task queue with `maxConcurrentDispatches: 1` per key to serialise instead.
- **Uniqueness** (`usernames/{name}`): `ref.create` in a transaction along with the profile update, or `create` alone if the profile update can lag.
- **Two-document consistency** (move note between folders, transfer credits): transaction; both refs read first.
- **Read a query then write** (`where("status","==","queued").limit(10)` → claim them): `tx.get(query)` then `tx.update` each; the query result set is locked. With many workers use a task queue instead.

## Error codes you will see

gRPC status numbers surface as `err.code`: `3 INVALID_ARGUMENT`, `4 DEADLINE_EXCEEDED`, `5 NOT_FOUND` (update on a missing doc), `6 ALREADY_EXISTS` (create on an existing doc), `7 PERMISSION_DENIED` (IAM, not rules — Admin SDK bypasses rules), `8 RESOURCE_EXHAUSTED` (quota), `9 FAILED_PRECONDITION` (missing index, or `update` precondition), `10 ABORTED` (contention; transactions retry this), `14 UNAVAILABLE` (transient). Map `5` → `not-found`, `6` → `already-exists`, `9` → `failed-precondition`, `10`/`14` → `unavailable` when surfacing to iOS via `HttpsError`.

## Does not exist / common mistakes

- `tx.get` after `tx.update` — throws; reorder.
- `await fetch(...)` or `await queue.enqueue(...)` inside the transaction callback — runs on every retry; move it out.
- `db.batch()` with a `get` — batches have no reads.
- More than 500 ops in a batch — commit throws; use BulkWriter or chunk.
- `bulkWriter.set(...)` in a loop then returning without `close()` — writes dropped.
- Treating `runTransaction` as a lock for external systems — it isolates Firestore reads/writes only.
- Using a transaction to "read many docs consistently" for a list endpoint — use `readOnly: true` or accept per-doc consistency; write transactions add contention for no benefit.
- Catching errors inside the callback and returning normally — the transaction commits partial intent; let it throw.
- `FieldValue.increment` inside a transaction after `tx.get` when you also computed the value manually — pick one: either write the computed value (`credits - cost`) or `increment(-cost)`; mixing both double-applies under retry confusion. Both are correct alone; `increment` is more robust when the read is only for validation.

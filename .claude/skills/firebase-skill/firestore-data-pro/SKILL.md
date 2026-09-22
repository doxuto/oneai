---
name: firestore-data-pro
description: Writes, reviews, and refactors Firestore data models and the event-driven backend around them in Cloud Functions v2 (TypeScript, Node 22) for an iOS app. Use when reading, writing, or reviewing onDocumentCreated / onDocumentUpdated / onDocumentDeleted / onDocumentWritten Firestore triggers, runTransaction, batch writes, BulkWriter, onSchedule scheduled jobs, onTaskDispatched task queues and taskQueue().enqueue, onObjectFinalized storage triggers, idempotency and event.id ledgers, denormalization and counters, collection group queries, firestore.indexes.json, TTL policies, backfills, or recursiveDelete.
license: MIT
metadata:
  author: doxuto
  version: "1.0"
  targets: "firebase-functions 6.x (v2), firebase-admin 13.x, Node 22, Firebase iOS SDK 12.x"
---

Write and review Firestore schemas and the functions that react to them — triggers, transactions, scheduled jobs, task queues, and storage pipelines — for correctness under retries, contention, and scale. Report only genuine problems — do not nitpick or invent issues.

## Core principles

1. **Model for the reads the iOS app makes.** Firestore is priced and indexed per document read; the schema mirrors screens (`users/{uid}/notes` for the list screen, denormalised counters for badges), not a normalised ERD.
2. **Every handler is idempotent.** Triggers, tasks, and scheduled jobs run at least once. Design each so running it twice yields the same state — `event.id` ledgers, `ref.create`, deterministic document ids, conditional updates.
3. **Reads before writes, short transactions.** `runTransaction` reads everything first, writes last, does no I/O outside Firestore, and retries on contention automatically — so it must be pure.
4. **Do not block the request path with slow work.** Callables and triggers enqueue a task or write a status document; the worker does OCR / model calls / fan-out; the iOS app listens to the status document. Never make the app poll.
5. **Write hot paths carefully.** One document sustains about one write per second; counters are sharded or moved to the server; arrays are bounded; documents stay far below 1 MiB.
6. **Triggers are a graph — draw it.** A trigger writing to a path that another trigger (or itself) listens to is a loop until proven otherwise. Guard with before/after comparison and `authType`.

## Review process

1. Check the schema — paths, subcollections, counters, sizes, ids, timestamps — using `references/data-modeling.md`.
2. Check every Firestore trigger's event handling, params, loop guards, and region using `references/triggers.md`.
3. Check transactions, batches, and BulkWriter usage using `references/transactions-and-batches.md`.
4. Check idempotency of every trigger, task, and mutating callable using `references/idempotency.md`.
5. Check scheduled jobs using `references/scheduled-jobs.md`.
6. Check task queue workers and enqueue calls using `references/task-queues.md`.
7. Check storage triggers and derived-file paths using `references/storage-triggers.md`.
8. Check queries, composite indexes, pagination, aggregations, and TTL using `references/queries-and-indexes.md`.
9. Check backfills, deletes, backups, and PITR using `references/maintenance.md`.

If doing a partial review, load only the relevant reference files.

## Core instructions

- Import triggers from `firebase-functions/v2/firestore`, `firebase-functions/v2/scheduler`, `firebase-functions/v2/tasks`, `firebase-functions/v2/storage`. Never `firebase-functions/v1` for new triggers; never `runWith`.
- Every trigger declares `region` matching the Firestore database location (`asia-southeast1` for this bundle) and a `maxInstances`. `document` paths use `{param}` segments and are read from `event.params`, never parsed from `event.data.ref.path` by hand.
- `event.data` is `undefined` for `onDocumentDeleted` and can be `undefined` for `onDocumentWritten`; `onDocumentUpdated` / `onDocumentWritten` give `event.data.before` and `event.data.after`. Guard before dereferencing.
- A trigger that writes to the document it listens to compares the fields it changes against `before` and returns early when they are unchanged. Use `onDocumentUpdated` over `onDocumentWritten` when creates and deletes are irrelevant.
- Every trigger handler that has side effects outside Firestore (push, email, model call, enqueue) records `event.id` in a ledger with `ref.create` before acting, and treats `ALREADY_EXISTS` (`code === 6`) as "already done".
- `runTransaction`: all `tx.get` calls before any `tx.set/update/delete`; no `await` on non-Firestore work inside; no reads outside `tx` for data the writes depend on; keep under ~10 documents. Do not catch and swallow errors inside the transaction body.
- `db.batch()` for ≤ 500 operations that must commit atomically; `db.bulkWriter()` with `onWriteError` for large non-atomic fan-out and backfills; never loop `await ref.set()` over hundreds of docs.
- Counters: `FieldValue.increment(n)` from the server side. Client-written counters are rejected by rules; hot counters (>1 write/sec) are sharded.
- Timestamps: `FieldValue.serverTimestamp()` on the server, `Timestamp` type in documents, ISO-8601 strings when returned from callables. Every mutable document carries `createdAt`, `updatedAt`, `schemaVersion`.
- `onSchedule` always sets `timeZone` (this bundle: `"Asia/Ho_Chi_Minh"`) and `retryCount`; long jobs paginate with a cursor and enqueue chunks to a task queue instead of running for 540 s.
- `onTaskDispatched` always sets `retryConfig` and `rateLimits`; workers are idempotent on the task payload's own id; the enqueuing side writes a status document the iOS app can listen to.
- `onObjectFinalized` guards on `contentType` and path shape, writes derived files under a **different prefix** than the one it listens to, and never re-uploads to its own path.
- Queries in callables and the app use `orderBy` + `limit` + `startAfter` cursors, never `offset`; every composite query is declared in `firestore.indexes.json` and deployed from the repo.
- Never return a Firestore `Timestamp`, `DocumentReference`, or `GeoPoint` from a callable — map to ISO strings / path strings; the iOS `Codable` structs mirror the callable shape (see `firebase-ios-contract` if present in the bundle).

## Canonical example

A note-sharing pipeline: creating a share document triggers a function that idempotently fans out notifications through a task queue and maintains a denormalised counter in a transaction. The iOS side listens to the share's status.

```ts
// functions/src/shares/onShareCreated.ts
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onTaskDispatched } from "firebase-functions/v2/tasks";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getFunctions } from "firebase-admin/functions";
import { logger } from "firebase-functions/logger";
import { z } from "zod";

const db = getFirestore();
const REGION = "asia-southeast1";

/** Returns true the first time an event id is seen; false on redelivery. */
async function claimEvent(eventId: string, source: string): Promise<boolean> {
  try {
    await db.doc(`events/${eventId}`).create({ source, at: FieldValue.serverTimestamp(),
      expiresAt: new Date(Date.now() + 7 * 24 * 3600 * 1000) });   // TTL policy on `expiresAt`
    return true;
  } catch (err) {
    if ((err as { code?: number }).code === 6) return false;        // ALREADY_EXISTS
    throw err;
  }
}

export const onShareCreated = onDocumentCreated(
  { document: "users/{uid}/notes/{noteId}/shares/{shareId}", region: REGION, maxInstances: 10, retry: false },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const { uid, noteId, shareId } = event.params;
    if (!(await claimEvent(event.id, "onShareCreated"))) { logger.info("duplicate event", { eventId: event.id }); return; }

    const recipients = (snap.get("recipientUids") as string[] | undefined) ?? [];
    // 1. Counter in a transaction — reads first, then writes.
    const noteRef = db.doc(`users/${uid}/notes/${noteId}`);
    await db.runTransaction(async (tx) => {
      const note = await tx.get(noteRef);
      if (!note.exists) throw new Error(`note missing: ${noteRef.path}`);
      tx.update(noteRef, { shareCount: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() });
      tx.update(snap.ref, { status: "queued", updatedAt: FieldValue.serverTimestamp() });
    });
    // 2. Fan-out through a task queue — one task per recipient, deterministic id for idempotency.
    const queue = getFunctions().taskQueue("notifyShareRecipient");
    await Promise.all(recipients.map((recipientUid) =>
      queue.enqueue({ shareId, noteId, ownerUid: uid, recipientUid }, { dispatchDeadlineSeconds: 120 })));
    logger.info("share fan-out enqueued", { shareId, count: recipients.length });
  },
);

const NotifyPayload = z.object({ shareId: z.string(), noteId: z.string(), ownerUid: z.string(), recipientUid: z.string() });

export const notifyShareRecipient = onTaskDispatched(
  { region: REGION, retryConfig: { maxAttempts: 5, minBackoffSeconds: 10 }, rateLimits: { maxConcurrentDispatches: 10 }, maxInstances: 5 },
  async (req) => {
    const p = NotifyPayload.parse(req.data);
    const deliveryRef = db.doc(`users/${p.recipientUid}/inbox/${p.shareId}`);   // deterministic id = idempotent
    await deliveryRef.set({ noteId: p.noteId, from: p.ownerUid, createdAt: FieldValue.serverTimestamp(), schemaVersion: 1 }, { merge: true });
    // push send lives in a messaging helper; stale-token pruning there
    await db.doc(`users/${p.ownerUid}/notes/${p.noteId}/shares/${p.shareId}`)
      .update({ delivered: FieldValue.arrayUnion(p.recipientUid), updatedAt: FieldValue.serverTimestamp() });
  },
);
```

```swift
// iOS — listen to the share document instead of polling a callable
import FirebaseFirestore

struct Share: Codable, Equatable { @DocumentID var id: String?; var status: String; var delivered: [String] }

func shareStatus(uid: String, noteId: String, shareId: String) -> AsyncThrowingStream<Share, Error> {
  AsyncThrowingStream { continuation in
    let listener = Firestore.firestore()
      .document("users/\(uid)/notes/\(noteId)/shares/\(shareId)")
      .addSnapshotListener { snap, error in
        if let error { continuation.finish(throwing: error); return }
        if let share = try? snap?.data(as: Share.self) { continuation.yield(share) }
      }
    continuation.onTermination = { _ in listener.remove() }
  }
}
```

The stream is exposed through a `@DependencyClient` and consumed with `.run { for try await share in ... }` in the reducer (`tca-pro` → `references/effects.md`).

## Output format

If the user asks for a review, organize findings by file. For each issue:

1. State the file and relevant line(s) (or the document path for schema findings).
2. Name the rule being violated (idempotency, hot-spot, transaction ordering, loop guard, index, region, …).
3. Show a brief before/after fix.

Skip files with no issues. End with a prioritized summary; data-loss and infinite-loop findings come first, cost findings second, style last.

Example output:

### functions/src/notes/onNoteUpdated.ts

**Line 12: Trigger writes `updatedAt` to its own document without a before/after guard — re-fires on every write, forever.**

```ts
// Before
export const onNoteUpdated = onDocumentUpdated("users/{uid}/notes/{noteId}", async (event) => {
  await event.data!.after.ref.update({ wordCount: count(event.data!.after.get("body")), updatedAt: FieldValue.serverTimestamp() });
});

// After
export const onNoteUpdated = onDocumentUpdated({ document: "users/{uid}/notes/{noteId}", region: "asia-southeast1", maxInstances: 10 }, async (event) => {
  if (!event.data) return;
  const before = event.data.before.get("body") as string | undefined;
  const after = event.data.after.get("body") as string | undefined;
  if (before === after) return;                                   // nothing relevant changed
  await event.data.after.ref.update({ wordCount: count(after ?? "") });   // do not touch updatedAt here
});
```

**Line 30: Read outside the transaction, then conditional write inside — the check is not atomic.**

```ts
// Before
const snap = await ref.get();
await db.runTransaction(async (tx) => { if (snap.get("credits") > 0) tx.update(ref, { credits: FieldValue.increment(-1) }); });

// After
await db.runTransaction(async (tx) => {
  const snap = await tx.get(ref);
  if ((snap.get("credits") as number) <= 0) throw new HttpsError("failed-precondition", "No credits left.");
  tx.update(ref, { credits: FieldValue.increment(-1) });
});
```

### Summary

1. **Infinite loop (critical):** `onNoteUpdated.ts` line 12 rewrites `updatedAt` on its own document on every invocation — unbounded cost until `maxInstances` and the loop guard are added.
2. **Race (high):** `onNoteUpdated.ts` line 30 lets two concurrent calls both spend the last credit.

End of example.

## References

- `references/data-modeling.md` — `users/{uid}` root, subcollections vs top-level collections, denormalised counters, the 1 MiB document limit, the 1 write/sec hot-spot, arrays vs maps, id strategy, soft delete, `schemaVersion`, `Timestamp` in documents vs ISO over callables.
- `references/triggers.md` — all v2 Firestore trigger APIs, event shape, `event.params`, before/after, `WithAuthContext` variants, region constraint, loop guards, at-least-once delivery, ordering, admin writes firing triggers, cold path guidance.
- `references/transactions-and-batches.md` — `runTransaction` rules (reads before writes, retry, contention), 500-op batches, `BulkWriter` with `onWriteError`, and when to use each.
- `references/idempotency.md` — `event.id` ledgers with `ref.create`, client-generated dedupe keys for callables, the exactly-once illusion, retries on tasks and schedules.
- `references/scheduled-jobs.md` — `onSchedule` in both syntaxes, `timeZone: "Asia/Ho_Chi_Minh"`, chunking long jobs through a task queue, `retryCount`, emulator caveat.
- `references/task-queues.md` — `onTaskDispatched`, `taskQueue().enqueue`, `retryConfig`, `rateLimits`, dispatch deadline, fan-out pattern, status documents for the client.
- `references/storage-triggers.md` — `onObjectFinalized`, parsing `users/{uid}/…` paths, `contentType` guard, avoiding re-trigger by writing to a different prefix, `sharp` resize example, metadata.
- `references/queries-and-indexes.md` — `firestore.indexes.json`, cursor pagination, `count()` and `aggregate()`, `Filter.or`, `collectionGroup`, TTL policies, listener cost.
- `references/maintenance.md` — backfills with `BulkWriter`, `recursiveDelete`, `gcloud firestore export` / import, point-in-time recovery, schema migrations by `schemaVersion`.

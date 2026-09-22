# Firestore triggers (v2)

Targets firebase-functions 6.x, `firebase-functions/v2/firestore`. Backed by Eventarc; every trigger is an event-driven Cloud Run service.

## APIs

```ts
import {
  onDocumentCreated, onDocumentUpdated, onDocumentDeleted, onDocumentWritten,
  onDocumentCreatedWithAuthContext, onDocumentUpdatedWithAuthContext,
  onDocumentDeletedWithAuthContext, onDocumentWrittenWithAuthContext,
  type FirestoreEvent, type Change, type QueryDocumentSnapshot, type DocumentSnapshot,
} from "firebase-functions/v2/firestore";
```

| Trigger | Fires on | `event.data` type |
|---|---|---|
| `onDocumentCreated` | first write of a doc | `QueryDocumentSnapshot \| undefined` |
| `onDocumentUpdated` | write that changes an existing doc (not creates, not deletes; not no-op writes) | `Change<QueryDocumentSnapshot> \| undefined` |
| `onDocumentDeleted` | delete | `QueryDocumentSnapshot \| undefined` (the deleted doc's last state) |
| `onDocumentWritten` | any of the above | `Change<DocumentSnapshot> \| undefined` — `before.exists` / `after.exists` tell you which |
| `...WithAuthContext` | same, plus `event.authType` and `event.authId` | same |

Two call forms — a path string with defaults, or an options object:

```ts
export const a = onDocumentCreated("users/{uid}/notes/{noteId}", async (event) => { /* … */ });
export const b = onDocumentCreated(
  { document: "users/{uid}/notes/{noteId}", region: "asia-southeast1", database: "(default)", namespace: "(default)",
    maxInstances: 10, memory: "256MiB", timeoutSeconds: 60, retry: false },
  async (event) => { /* … */ },
);
```

Always use the options object in this bundle so `region` and `maxInstances` are explicit.

## Event shape

```ts
export const onNoteWritten = onDocumentWritten(
  { document: "users/{uid}/notes/{noteId}", region: "asia-southeast1", maxInstances: 10 },
  async (event: FirestoreEvent<Change<DocumentSnapshot> | undefined, { uid: string; noteId: string }>) => {
    if (!event.data) return;
    const { uid, noteId } = event.params;         // typed from the path template
    event.id;                                      // unique per delivery attempt group — same id on redelivery
    event.time;                                    // RFC3339 string; commit time
    event.source; event.type;                      // "google.cloud.firestore.document.v1.written"
    event.document;                                // "users/u1/notes/n1" (path without databases/… prefix)
    event.database; event.namespace;

    const before = event.data.before;             // DocumentSnapshot; .exists false on create
    const after = event.data.after;               // DocumentSnapshot; .exists false on delete
    if (!before.exists && after.exists) { /* create */ }
    else if (before.exists && !after.exists) { /* delete */ }
    else { /* update */ }

    after.ref;                                     // DocumentReference — write with it, no need to rebuild the path
    after.get("title");                            // field access
    after.data();                                  // whole doc (undefined if !exists)
    after.updateTime; after.createTime;
  },
);
```

`event.params` keys come from `{name}` segments; wildcard `{path=**}` is not supported in Firestore trigger templates (only single-segment params). A trigger on `users/{uid}/notes/{noteId}` does **not** fire for `users/{uid}/notes/{noteId}/shares/{shareId}`; each subcollection needs its own trigger.

Snapshots inside the handler are **plain snapshots, not live**: `after.data()` is the state at commit time, not the current state. If the handler needs the current state (because other writes may have landed since), read again — inside a transaction if you are going to write conditionally.

## Auth context

```ts
export const onNoteCreated = onDocumentCreatedWithAuthContext(
  { document: "users/{uid}/notes/{noteId}", region: "asia-southeast1" },
  async (event) => {
    event.authType;   // "app_user" | "system" | "service_account" | "unauthenticated" | "unknown"
    event.authId;     // uid for app_user; service account email for service_account; undefined otherwise
    if (event.authType === "service_account") return;   // written by our own functions — skip re-processing
  },
);
```

`app_user` = client SDK with a Firebase ID token (the iOS app). `service_account` = Admin SDK from a function or script. `system` = Firestore itself (TTL deletions, imports). Use it to (a) skip loops caused by your own writes, (b) audit who changed a document, (c) reject/undo client writes that should have gone through a callable (rare; prefer rules).

## Region constraint

Firestore triggers must be deployed where the database can deliver events:

- Regional database (`asia-southeast1`) → trigger `region: "asia-southeast1"`.
- Multi-region `nam5` → `us-central1`; `eur3` → `europe-west4` (verify the current mapping in firebase docs if the database is multi-region).

A mismatch fails at deploy with an Eventarc error. This bundle: database and all triggers in `asia-southeast1`. The `database` option targets a named database (`getFirestore("other")` on the admin side); default is `"(default)"`.

## Loop guards

A trigger that writes to any document that a trigger listens to (its own path included) re-fires that trigger. Every such write needs a guard:

```ts
export const onNoteUpdated = onDocumentUpdated(
  { document: "users/{uid}/notes/{noteId}", region: "asia-southeast1", maxInstances: 10 },
  async (event) => {
    if (!event.data) return;
    const before = event.data.before.data();
    const after = event.data.after.data();
    // 1. Only react to the fields you care about.
    if (before.body === after.body && before.title === after.title) return;
    // 2. Only write fields you do not react to, and only when they actually change.
    const wordCount = countWords(after.body ?? "");
    if (after.wordCount === wordCount) return;
    await event.data.after.ref.update({ wordCount });        // no updatedAt bump — that would loop if `updatedAt` mattered
  },
);
```

Rules of thumb:

- Compare `before` vs `after` on the inputs; compare the computed output against the stored value before writing.
- Never bump `updatedAt` from a trigger that listens to updates of the same doc unless the guard ignores `updatedAt`.
- Prefer `onDocumentUpdated` over `onDocumentWritten` when creates/deletes do not matter — fewer invocations, fewer edge cases.
- Two triggers on different paths that write to each other's paths form a cycle. Draw the trigger graph (path → trigger → writes) and check for cycles in review.
- `maxInstances` bounds the blast radius of a loop you missed.

## Delivery semantics

- **At least once.** Redelivery happens on timeout, crash, unhandled rejection, or infrastructure retry. `event.id` is stable across redeliveries — the idempotency key (`idempotency.md`).
- **`retry: false` (default)** — a failed invocation is not retried by Eventarc; the event is dropped after the first failure (Eventarc still may redeliver in rare cases). **`retry: true`** — failures are retried with backoff for up to 7 days. Use `retry: true` only for handlers that are idempotent *and* whose failure is transient (network); a permanent failure (bad data) with `retry: true` retries for a week — validate and return early instead of throwing on bad input.
- **Ordering is not guaranteed.** Two rapid writes to one doc can arrive out of order; use `event.time` or `after.updateTime` to reject stale events (`if (stored.updatedAt > event.time) return`), or make the handler compute from `after` only (idempotent by construction).
- **Latency** is typically sub-second but can spike to seconds; cold starts add more. The iOS app must not assume the derived write is visible immediately after its own write — show optimistic UI and listen.
- **Delivery timeout** is the function's `timeoutSeconds` (default 60, max 540 for event functions). Long work goes to a task queue (`task-queues.md`).
- Events are **not delivered** for writes that happened while the trigger did not exist (deploy gap); backfill after adding a trigger (`maintenance.md`).

## Admin writes fire triggers too

Writes from the Admin SDK, `BulkWriter`, batches, transactions, `recursiveDelete`, imports, and TTL deletions all fire triggers (imports and TTL show `authType: "system"`). Consequences:

- A backfill over 100 k documents fires 100 k trigger invocations. Either make the trigger cheap/idempotent, temporarily undeploy it, or write a marker field the trigger checks (`if (after.get("_backfill")) return`) and strip it afterwards.
- `recursiveDelete(users/{uid})` fires `onDocumentDeleted` for every doc — good for cleanup cascades, expensive if those handlers do external calls. `deleteAccount` should mark `status: "deleting"` first so delete triggers can skip side effects.
- No-op writes (`set` with identical data) do **not** fire `onDocumentUpdated` — Firestore only emits an event when the document actually changes. `update({ updatedAt: serverTimestamp() })` always changes it.

## Errors and logging

- Throwing (or a rejected promise) marks the invocation failed → Error Reporting entry, and retry only if `retry: true`. For "this event is not for me" return normally; for "bad data, never retry" log `warn` and return; for "transient, please retry" throw.
- Log `event.id`, `event.document`, and params on every non-trivial branch — it is the only way to correlate redeliveries.
- A handler must `await` everything it starts. A dangling promise is killed when the function returns and its work may or may not happen.

## Cold path

Triggers are async and off the user's request path, so cold-start latency matters less than in callables — but not zero: a note created → thumbnail/counters/search-index chain should finish within a few seconds for the UI to feel live. Keep module top-level light (no `sharp` import at top level of a module that also exports light triggers — split codebases or lazy-import), set `memory` per trigger (`sharp` needs ≥ 512 MiB), and do not set `minInstances` on triggers unless a product SLA demands it.

## Testing

`firebase-functions-test` 3.x: `test.firestore.makeDocumentSnapshot(data, "users/u1/notes/n1")` and `test.makeChange(before, after)`; call `test.wrap(onNoteUpdated)({ data: change, params: { uid: "u1", noteId: "n1" } })`. Integration: run the emulator, write with the Admin SDK pointed at `FIRESTORE_EMULATOR_HOST`, assert the derived write with a polling `waitFor`. Full recipes in `firebase-testing-pro`.

## Does not exist / common mistakes

- `functions.firestore.document("…").onCreate((snap, context) => …)` — v1. v2 is `onDocumentCreated({ document }, (event) => …)`; `snap` is `event.data`, `context.params` is `event.params`.
- `event.data.data()` on `onDocumentUpdated` — `event.data` is a `Change`; use `event.data.after.data()`.
- `event.data.ref` on a delete to `.update()` — the doc is gone; `update` throws NOT_FOUND. Use `set` if you need to recreate, or write elsewhere.
- `enforceAppCheck` / `cors` / `invoker` on a Firestore trigger — HTTP-only options.
- Wildcards like `users/{uid}/{collection}/{docId}` or `{path=**}` — not supported; Firestore triggers need literal collection names.
- Assuming `onDocumentUpdated` fires for creates — it does not; use `onDocumentWritten` or two triggers.
- Relying on trigger ordering to build a sequence (e.g. counting events) — use `event.time` comparisons or compute from `after` state.
- `retry: true` on a handler that throws on validation errors — retries a poison event for 7 days.
- Deploying a trigger to `us-central1` for an `asia-southeast1` database — deploy fails; region must match.
- Expecting triggers to skip Admin SDK writes — they fire; guard with `authType` or before/after comparison.

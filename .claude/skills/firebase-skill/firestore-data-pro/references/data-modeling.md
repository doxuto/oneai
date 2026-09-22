# Firestore data modeling

Targets Cloud Firestore (Native mode), firebase-admin 13.x, Firebase iOS SDK 12.x (`FirebaseFirestore` with `Codable`).

## Hard limits to design around

| Limit | Value | Consequence |
|---|---|---|
| Max document size | 1 MiB (1 048 576 bytes, including field names and the path) | Long text, arrays of items, and embedded histories must move to subcollections or Storage |
| Sustained writes per document | ~1 per second | Counters, "last seen", presence, and global stats need sharding or server-side batching |
| Max depth of subcollections | 100 | Not a practical limit; 2–3 levels is the norm |
| Max field name / path | 1 500 bytes | Do not use user content as ids |
| Max array/map indexable entries | 20 000 index entries per document by default | Every array element and map key is indexed; large maps of maps blow the index limit |
| Max writes per transaction / batch | 500 | Fan-out beyond that uses BulkWriter |
| Max `in` / `array-contains-any` values | 30 | Chunk larger id lists |
| Reads | billed per document, including listener re-sends | Model for the read shape of each screen |

## The `users/{uid}` root

Everything the user owns lives under `users/{uid}`. Rules become a path compare (`request.auth.uid == uid`), deletion is `recursiveDelete(users/{uid})`, export is one subtree, and triggers get `uid` from `event.params`.

```
users/{uid}                                  profile, plan mirror, counters, schemaVersion
users/{uid}/notes/{noteId}                   user content
users/{uid}/notes/{noteId}/shares/{shareId}  per-note child records
users/{uid}/scans/{scanId}                   pipeline status docs the app listens to
users/{uid}/devices/{installationId}         FCM tokens
users/{uid}/quota/{key}                      server-only counters
users/{uid}/inbox/{itemId}                   things other users sent to me (written by functions)
events/{eventId}                             idempotency ledger, TTL, server-only
_meta/{key}                                  schema/version markers, server-only
```

Top-level collections are for data that is **not owned by one user**: `orgs/{orgId}`, `publicNotes/{noteId}`, `catalog/{sku}`. If a query needs "all notes of one user" it belongs under the user; if it needs "all public notes across users" it is top-level or a collection group.

## Subcollections vs top-level collections

| Choose a subcollection when | Choose top-level when |
|---|---|
| Access is always scoped by the parent (my notes, this note's shares) | Queries span parents (all shares to me, all public notes) |
| Rules should inherit ownership from the path | Rules need `resource.data.ownerId` anyway |
| Deletion should cascade with the parent (`recursiveDelete`) | Items outlive the parent |
| Size would push the parent doc toward 1 MiB | Item count per parent is small and stable (≤ 20) — then a map field may do |

Collection groups (`db.collectionGroup("shares")`) give cross-parent queries over subcollections at the cost of a collection-group index and a rule that must be provable for every document (see `queries-and-indexes.md`, `firebase-security-pro` → `firestore-rules.md`). Denormalise the fields the group query filters on (`ownerId`, `recipientUids`) into the subcollection docs.

## Denormalised counters and summaries

Firestore has no cheap `COUNT(*)` for listeners (aggregation queries are one-shot). Keep a counter on the parent, maintained by the server:

```ts
// trigger on users/{uid}/notes/{noteId} create/delete
tx.update(db.doc(`users/${uid}`), { noteCount: FieldValue.increment(delta) });
```

- Written by functions/Admin SDK only; rules put `noteCount` in the update deny-list.
- Cheap to read (it is on the doc the app already listens to).
- Drifts if a trigger is missed or double-fired — so triggers are idempotent (`idempotency.md`) and a scheduled job reconciles with `count()` nightly (`scheduled-jobs.md`).
- Hot counters (likes on a viral doc, global stats) exceed 1 write/sec. Options: **distributed counter** (`counters/{id}/shards/{0..N}` with `increment`, read = sum of shards), or write increments to a task queue that coalesces, or accept eventual consistency by sampling. Per-user counters are rarely hot.

Summaries: store `lastNote: { id, title, updatedAt }` on the user doc when the list screen only needs a preview; update it in the same transaction as the note. Duplicate data is fine; duplicate **sources of truth** are not — pick one document as canonical and derive the rest in triggers.

## Arrays vs maps

- Arrays: ordered, `arrayUnion`/`arrayRemove` are idempotent set operations, `array-contains` / `array-contains-any` (≤ 30 values) queries. No positional update (you rewrite the whole array), no per-element rules. Bound them: `recipientUids` ≤ 20 enforced in zod and rules (`size() <= 20`).
- Maps: keyed lookup, dot-path updates (`tx.update(ref, { "settings.theme": "dark" })`), per-key rules (`affectedKeys()`), and `FieldValue.delete()` on one key. Every key is indexed unless the collection has a field exemption — a map with thousands of dynamic keys (`readBy: { uid1: true, uid2: true, ... }`) becomes both a size and index problem; move it to a subcollection past ~100 keys.
- Do not store an array of objects that you need to update individually — `[{ id, done }]` requires read-modify-write of the whole array under contention; use a subcollection or a map keyed by id.

## Document ids

- Auto ids (`collection.doc()` / `doc().id`) are 20 chars, random, well distributed. Default choice.
- Deterministic ids for idempotency and uniqueness: `users/{uid}/devices/{installationId}`, `users/{uid}/inbox/{shareId}`, `events/{eventId}`, `usernames/{lowercasedName}` (uniqueness via `create`).
- Never use monotonically increasing ids (`timestamp`, sequence numbers) for high-write collections — they hot-spot the index range. Never use user content (email, title) as an id — size limit and PII in paths.
- Client-generated `UUID().uuidString` from iOS is fine as a doc id and doubles as the dedupe key for callables (`idempotency.md`).

## Timestamps

- In documents: `Timestamp` (`FieldValue.serverTimestamp()` on write from any side; rules enforce `== request.time` for client writes). Never store ISO strings or millis in documents — they lose type checks and range queries behave lexically.
- Over callables: `Timestamp` does **not** serialise. Convert: `ts.toDate().toISOString()` outbound; inbound `Timestamp.fromDate(new Date(iso))` after zod `z.string().datetime()`. iOS `Codable` structs use `Date` with `.iso8601` strategy for callables and `@ServerTimestamp var createdAt: Date?` when decoding Firestore snapshots directly.
- Every mutable document: `createdAt`, `updatedAt` (server-set). Server-written docs set them with `FieldValue.serverTimestamp()`; client-written docs must too (rules check).
- Use `Timestamp` for TTL fields (`expiresAt`) — the TTL policy only recognises `Timestamp` (or a Date that becomes one).

## Soft delete

`isDeleted: boolean` + `deletedAt: Timestamp` on the doc, filtered out with `where("isDeleted", "==", false)` in every list (which makes `isDeleted` part of every composite index — accept it) and purged by a scheduled job after 30 days. Use it when the app offers "Recently deleted" or undo; otherwise hard delete. Rules: owner may set `isDeleted: true`; only the server may hard delete (`allow delete: if false`) if you need audit.

## `schemaVersion`

Every document type carries `schemaVersion: number` set on create. Readers (functions and iOS) branch on it; migrations bump it in place (`maintenance.md`). Without it you cannot tell a v1 doc from a v2 doc with a missing field. Put the current version constant in one shared module and in rules (`incoming().schemaVersion == 2` on create).

## Example schema (TypeScript types shared by all functions)

```ts
// functions/src/model/types.ts
import type { Timestamp } from "firebase-admin/firestore";

export const NOTE_SCHEMA_VERSION = 2;

export interface UserDoc {
  displayName: string;
  locale: string;
  plan: "free" | "pro";           // mirror of the custom claim; server-written
  noteCount: number;              // denormalised; server-written
  status?: "active" | "deleting";
  schemaVersion: number;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export interface NoteDoc {
  ownerId: string;                // == path uid; needed for collection-group rules/queries
  title: string;                  // ≤ 200 chars (zod + rules)
  body?: string;                  // ≤ 20 000 chars; longer content goes to Storage
  tags: string[];                 // ≤ 10
  shareCount: number;             // server-written
  isDeleted: boolean;
  deletedAt?: Timestamp;
  schemaVersion: number;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export interface ScanDoc {
  status: "uploading" | "queued" | "processing" | "done" | "failed";
  pageCount: number;
  ocrText?: string;               // if this can exceed ~200 KB, store in Storage and keep a path here
  extracted?: Record<string, unknown>;
  error?: { code: string; message: string };   // client-safe message only
  taskId?: string;
  schemaVersion: number;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}
```

Use `withConverter` on the Admin SDK for typed reads: `db.collection("users").withConverter<UserDoc>({ toFirestore: (d) => d, fromFirestore: (s) => s.data() as UserDoc })`.

## iOS mirror

The Swift model mirrors field names exactly (camelCase), decodes snapshots with `snap.data(as: Note.self)`, and uses `@DocumentID var id: String?` + `@ServerTimestamp var createdAt: Date?`. Keep one `Codable` per document type in a shared module; do not reuse callable DTOs (which carry ISO strings) for snapshot decoding (which carry `Timestamp`). Firestore access is behind a `@DependencyClient` (`tca-pro` → `references/dependencies.md`).

## Does not exist / common mistakes

- Joins — Firestore has none; a screen that needs data from two collections either denormalises or does two reads. Do not build a "join in a callable" that fans out N reads per list item.
- `LIKE`/full-text search — not supported; `>=` / `<` prefix tricks on a lowercased field, or Algolia/Typesense via a trigger.
- Storing an entire chat history / all pages of OCR text in one document — hits 1 MiB; one doc per message/page.
- Unbounded arrays (`viewedBy`, `likes`) — size limit and rewrite contention; subcollection.
- Field names starting with `__` — reserved.
- Storing `null` vs omitting — both are queryable differently (`== null` matches only explicit null). Pick one convention per field; `ignoreUndefinedProperties: true` on the Admin SDK drops `undefined` silently.
- Counting with `collection.get().size` — reads every document; use `count()`.
- Using `Date` in Admin writes and expecting `Timestamp` back — the SDK converts `Date` → `Timestamp` on write; on read you always get `Timestamp`. Types that say `Date` for Firestore fields are wrong.

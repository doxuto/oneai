# Queries, indexes, aggregations, TTL, and listener cost

Targets firebase-admin 13.x (`firebase-admin/firestore`), Firebase iOS SDK 12.x, `firestore.indexes.json` deployed with the Firebase CLI.

## Index basics

- Every field gets a single-field index automatically (ascending, descending, array-contains). Equality filters on one field and `orderBy` on one field need nothing.
- A query with **two or more** of: range/inequality on a field, `orderBy` on a different field, `array-contains` + another clause, needs a **composite index**. Missing one fails at runtime with `FAILED_PRECONDITION: The query requires an index` plus a console link. The Admin SDK error also carries that link — copy the definition into `firestore.indexes.json`, never click-create in production only.
- Composite indexes live in the repo and deploy with `firebase deploy --only firestore:indexes`. Building takes minutes for large collections; deploy indexes **before** the code that needs them.
- `firebase firestore:indexes` prints the current deployed set as JSON — use it to sync the file after a console experiment.

```json
{
  "indexes": [
    {
      "collectionGroup": "notes",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "isDeleted", "order": "ASCENDING" },
        { "fieldPath": "updatedAt", "order": "DESCENDING" }
      ]
    },
    {
      "collectionGroup": "notes",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        { "fieldPath": "ownerId", "order": "ASCENDING" },
        { "fieldPath": "isDeleted", "order": "ASCENDING" },
        { "fieldPath": "deletedAt", "order": "ASCENDING" }
      ]
    },
    {
      "collectionGroup": "notes",
      "queryScope": "COLLECTION",
      "fields": [
        { "fieldPath": "tags", "arrayConfig": "CONTAINS" },
        { "fieldPath": "updatedAt", "order": "DESCENDING" }
      ]
    }
  ],
  "fieldOverrides": [
    {
      "collectionGroup": "scans",
      "fieldPath": "ocrText",
      "indexes": []
    },
    {
      "collectionGroup": "events",
      "fieldPath": "expiresAt",
      "ttl": true,
      "indexes": [{ "order": "ASCENDING", "queryScope": "COLLECTION" }]
    }
  ]
}
```

- `queryScope: "COLLECTION"` — for `db.collection("users/u1/notes")`; `"COLLECTION_GROUP"` — for `db.collectionGroup("notes")`. Same fields, separate index entries.
- `fieldOverrides` with `"indexes": []` **exempts** a field from single-field indexing — do this for large text (`ocrText`, `body`), big maps, and anything you never query; it cuts write cost and avoids the 20 000-entries-per-document limit.
- `"ttl": true` in a field override declares the TTL policy in the same file (supported by firebase-tools; verify your version). Otherwise `gcloud firestore fields ttls update expiresAt --collection-group=events --enable-ttl`.
- Order of `fields` matters: equality fields first, then the range/`orderBy` field, then `__name__` implicitly.

## Query shapes

```ts
import { getFirestore, Filter, FieldPath, Timestamp, AggregateField } from "firebase-admin/firestore";
const db = getFirestore();
const notes = db.collection(`users/${uid}/notes`);

// Equality + order + limit (composite: isDeleted ASC, updatedAt DESC)
await notes.where("isDeleted", "==", false).orderBy("updatedAt", "desc").limit(20).get();

// Range on the same field as orderBy — allowed with one index on that field
await notes.where("updatedAt", ">", since).orderBy("updatedAt").get();

// Inequality on a different field than orderBy — allowed since 2024 (multiple inequality support), still needs a composite index
await notes.where("shareCount", ">", 0).where("updatedAt", ">", since).orderBy("updatedAt", "desc").get();

// OR
await notes.where(Filter.or(Filter.where("tags", "array-contains", "work"), Filter.where("isPinned", "==", true))).get();
// `in` / `array-contains-any` / `not-in`: ≤ 30 values; chunk larger lists
await db.collection("users").where(FieldPath.documentId(), "in", uids.slice(0, 30)).get();

// Collection group (needs COLLECTION_GROUP index + a rule the app can prove — see firebase-security-pro)
await db.collectionGroup("shares").where("recipientUids", "array-contains", uid).orderBy("createdAt", "desc").limit(50).get();

// Projection: fetch only what you need (still billed per document)
await notes.select("title", "updatedAt").limit(100).get();
await notes.select().get();   // ids only — for backfills and deletes
```

Rules interplay: a client query must contain the clauses the `list` rule needs to be provable (`where("ownerId", "==", uid)` for collection groups). Write the query, the rule, and the index together.

## Cursor pagination

Never `offset(n)` — it reads and bills the skipped documents. Use `startAfter` with the last snapshot (or its sort values) and a total order (`orderBy` field + `__name__` tie-break is implicit).

```ts
const PAGE = 20;
export async function listNotes(uid: string, cursor?: string): Promise<{ items: NoteDTO[]; nextCursor?: string }> {
  let q = db.collection(`users/${uid}/notes`).where("isDeleted", "==", false).orderBy("updatedAt", "desc").orderBy(FieldPath.documentId()).limit(PAGE + 1);
  if (cursor) {
    const { updatedAt, id } = decodeCursor(cursor);              // base64url JSON { updatedAt: millis, id }
    q = q.startAfter(Timestamp.fromMillis(updatedAt), id);
  }
  const snap = await q.get();
  const docs = snap.docs.slice(0, PAGE);
  const last = docs[docs.length - 1];
  return {
    items: docs.map(toDTO),                                       // Timestamps → ISO strings
    nextCursor: snap.size > PAGE && last ? encodeCursor({ updatedAt: last.get("updatedAt").toMillis(), id: last.id }) : undefined,
  };
}
```

- Fetch `limit + 1` to know whether a next page exists without a `count()`.
- Opaque string cursors over callables; the iOS `Codable` DTO carries `nextCursor: String?`. Do not pass a `DocumentSnapshot` shape through a callable.
- On the iOS side with direct Firestore reads, `query.start(afterDocument: lastSnapshot)` does the same; keep the same `orderBy` chain on both sides and in the index.
- `endBefore` / `limitToLast` for backwards paging; `startAt` for "jump to".

## Aggregations

```ts
const c = await notes.where("isDeleted", "==", false).count().get();
c.data().count;                                          // number

const agg = await db.collection(`users/${uid}/ledger`).aggregate({
  total: AggregateField.sum("delta"),
  avg: AggregateField.average("delta"),
  n: AggregateField.count(),
}).get();
agg.data().total; agg.data().avg; agg.data().n;
```

- Billed per **1 000 index entries scanned** (minimum one read) — far cheaper than fetching documents, but not free at millions of rows; results are not cached and there is no listener form (one-shot only).
- `count()` obeys the same index requirements as the underlying query.
- iOS: `query.count.getAggregation(source: .server)` / `query.aggregate([AggregateField.sum("delta")]).getAggregation(source: .server)`.
- For a badge that updates live, keep a denormalised counter (`data-modeling.md`) and reconcile with `count()` nightly.

## TTL policies

- One TTL field per collection group; must be a `Timestamp` (or `Date` written by the Admin SDK). Documents are deleted **within about 24 hours** after the timestamp, not at it — TTL is for cleanup, not for enforcing expiry; queries must still filter `where("expiresAt", ">", now)` if expiry matters.
- Enable per collection group: console (Firestore → TTL) or `gcloud firestore fields ttls update expiresAt --collection-group=events --enable-ttl --project=snaptool-prod`, or the `fieldOverrides` form above.
- TTL deletes fire `onDocumentDeleted` with `authType: "system"`; they are billed as normal deletes.
- Typical TTL collections: `events` (ledger), `_ratelimit`, `exports`, `sessions`, pending invitations, `_meta/leases`.

## Listener cost and shape

Snapshot listeners are billed per document **initially delivered plus each changed document delivered**, plus a minimum of one read per 30 minutes of an idle listener (verify current pricing notes). Design implications:

- Listen to **small, bounded** sets: one document (`users/{uid}/scans/{scanId}`), or a paginated list with `limit`. A listener on `users/{uid}/notes` without a limit re-delivers the whole growing collection on first attach every launch.
- The iOS SDK's local cache serves reads offline and dedupes unchanged docs; `includeMetadataChanges` should stay `false` in TCA effects to avoid double emissions.
- Prefer one listener on a parent summary doc over N listeners on children. Fan-in server-side (the completion trigger in `task-queues.md`).
- Detach listeners in `onTermination` (see the SKILL.md canonical example); a leaked listener is billed until the app dies.
- Rules cost: each `get()`/`exists()` in the rule is evaluated per listener attach and per re-evaluation; keep rules for listened paths free of document lookups.
- Bundles (`db.bundle()` / `loadBundle` on iOS) are a way to ship a large initial dataset cheaply — mention, do not default to it.

## Missing-index and query errors from callables

Map `FAILED_PRECONDITION` (code 9) with "requires an index" to `HttpsError("internal")` and log the message with the index link — the client can do nothing about it, and the link is exactly what the on-call person needs. Do not return the raw message (it includes the project id and collection names).

## Does not exist / common mistakes

- `offset()` for paging — bills skipped docs; use cursors.
- `!=` / `not-in` as the only filter to "exclude a few" — it still scans the whole index and excludes docs where the field is missing.
- `orderBy` on a field that some documents lack — those documents are excluded from results silently.
- `where("a", "==", x).where("a", "==", y)` — always empty; use `in`.
- A collection-group query without `COLLECTION_GROUP` scope in the index — fails with the index error even though a `COLLECTION` index on the same fields exists.
- Indexing large text fields by default — every write updates the index; exempt them in `fieldOverrides`.
- `count()` in a listener — no such API; one-shot only.
- Relying on TTL for security-relevant expiry — up to 24 h late; filter in the query and rules.
- Editing indexes only in the console — drift between projects; keep `firestore.indexes.json` canonical and deploy it in CI.
- Text search with `>=` prefix tricks on a case-sensitive field — store `titleLower` and search that; anything more than prefix needs an external index.

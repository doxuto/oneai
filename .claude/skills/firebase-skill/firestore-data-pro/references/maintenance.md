# Maintenance: backfills, migrations, deletes, backups, PITR

Targets firebase-admin 13.x, Firebase CLI, `gcloud firestore`. Everything here runs as a script (`functions/scripts/*.ts` with `tsx`, authenticated via ADC: `gcloud auth application-default login` against the right project) or as a one-off callable/scheduled function — never from the iOS app.

## Backfills with BulkWriter

Adding a field, computing a derived value, or fixing bad data across a whole collection.

```ts
// functions/scripts/backfill-note-schema-v2.ts   — run: npx tsx scripts/backfill-note-schema-v2.ts --project snaptool-dev [--apply]
import { initializeApp } from "firebase-admin/app";
import { getFirestore, FieldValue, type QueryDocumentSnapshot } from "firebase-admin/firestore";

const APPLY = process.argv.includes("--apply");
initializeApp({ projectId: process.argv[process.argv.indexOf("--project") + 1] });
const db = getFirestore();

async function main() {
  const bw = db.bulkWriter();
  let scanned = 0, updated = 0, failed = 0;
  bw.onWriteError((err) => { failed++; console.error(err.documentRef.path, err.code, err.message); return err.failedAttempts < 3; });

  // Only docs that still need it: makes the script resumable and idempotent.
  let q = db.collectionGroup("notes").where("schemaVersion", "<", 2).orderBy("schemaVersion").orderBy("__name__").limit(500);
  let last: QueryDocumentSnapshot | undefined;
  for (;;) {
    const page = await (last ? q.startAfter(last) : q).get();
    if (page.empty) break;
    for (const doc of page.docs) {
      scanned++;
      const patch = { schemaVersion: 2, isDeleted: doc.get("isDeleted") ?? false, shareCount: doc.get("shareCount") ?? 0, _backfill: true };
      if (APPLY) { bw.update(doc.ref, patch); updated++; }
    }
    await bw.flush();
    last = page.docs[page.docs.length - 1];
    console.log(`scanned=${scanned} updated=${updated} failed=${failed}`);
  }
  await bw.close();
  console.log(APPLY ? "done" : "dry run — re-run with --apply");
}
main().catch((e) => { console.error(e); process.exit(1); });
```

Rules of a safe backfill:

- **Dry run first.** Count and sample; print a handful of before/after diffs.
- **Query only the docs that need the change** so a re-run after a crash continues where it left off and does nothing on already-migrated docs.
- **Paginate with cursors**, `flush()` per page; do not load a million docs into memory.
- **Triggers fire** for every write. Either make triggers cheap and idempotent (they should be), mark writes with a `_backfill: true` field the triggers check (`if (after.get("_backfill")) return`) and strip it afterwards, or temporarily deploy the trigger with an early return. Estimate: 1 M docs × trigger cost.
- **Rate**: BulkWriter ramps up automatically (500 ops/s → doubling every 5 min). For very large collections run the script from a Compute VM in the same region to avoid egress and latency; from a laptop expect ~200–500 writes/s.
- **Run on dev first**, then staging, then prod with the same script and the same commit.
- **Never `set` without `merge`** in a backfill unless the intent is to replace the doc; `update` fails on missing docs (good — it surfaces surprises).

## Schema migrations by `schemaVersion`

1. Add the new field as optional in TypeScript and in rules (`!('newField' in d) || d.newField is …`). Deploy functions that tolerate both versions. Ship the iOS build that tolerates both (Codable with optionals / `decodeIfPresent`).
2. Backfill old docs (above), bumping `schemaVersion`.
3. Make the field required in rules for `create` with `schemaVersion == 2`; keep accepting v1 updates until the old app version is below your support floor.
4. Remove v1 branches from code once `count()` of `schemaVersion < 2` is zero.

Renaming a field is add-new → backfill → switch readers → stop writing old → delete old (`FieldValue.delete()` in a second backfill). Never rename in place in one step; old app versions in the wild still write the old name.

## Deleting data

```ts
// Document + all subcollections (uses BulkWriter internally; pass your own to observe errors)
await db.recursiveDelete(db.doc(`users/${uid}`));
// Whole collection (top-level or sub)
await db.recursiveDelete(db.collection("legacyNotes"));
// Query-scoped delete: page + BulkWriter (recursiveDelete takes a ref, not a query)
```

- `recursiveDelete` is the right primitive for `deleteAccount` and for tearing down test data; it fires `onDocumentDeleted` for every document.
- Firebase CLI: `firebase firestore:delete users/u1 --recursive` / `firebase firestore:delete --all-collections` (the latter is for emulators and disposable projects only; it prompts).
- Deleting a collection does not delete its composite indexes or TTL policies; clean `firestore.indexes.json`.
- Storage is separate: `bucket.deleteFiles({ prefix })`.

## Exports and backups

Two mechanisms; use both.

**Managed export** (point-in-time snapshot of the database to a GCS bucket, importable into any project — this is the disaster-recovery and environment-cloning tool):

```sh
gcloud firestore export gs://snaptool-prod-backups/$(date +%F) --project=snaptool-prod \
  --collection-ids=users,notes,shares            # optional; omit for everything (required when importing a subset)
gcloud firestore import gs://snaptool-prod-backups/2026-09-15 --project=snaptool-staging
```

- The bucket should be in the same location as the database (`asia-southeast1`), with a lifecycle rule (delete after 30/90 days) and no public access. Grant the Firestore service agent `Storage Admin` on it once (the error message names the exact principal on first run).
- Exports are billed as reads of every document; imports as writes. Nightly for a small app is fine; weekly plus PITR for a large one.
- Schedule it: `onSchedule` calling the Firestore Admin REST API via `@google-cloud/firestore`'s `v1.FirestoreAdminClient().exportDocuments({ name: "projects/p/databases/(default)", outputUriPrefix: "gs://…" })` — the function's service account needs `datastore.databases.export` (role **Cloud Datastore Import Export Admin**) and write access to the bucket. Verify the client class name against the current `@google-cloud/firestore` docs.
- Import into a **fresh** project to rehearse restores; importing into a live database overwrites documents with the same ids and fires triggers (`authType: "system"`).
- Export files are not human-readable; for per-user data export (GDPR) write JSON yourself (`firebase-security-pro` → `secrets-and-pii.md`).

**Scheduled backups** (Firestore-native, retained by the service, restorable to a new database):

```sh
gcloud firestore backups schedules create --database='(default)' --recurrence=daily --retention=7d --project=snaptool-prod
gcloud firestore backups list --location=asia-southeast1
gcloud firestore databases restore --source-backup=projects/p/locations/asia-southeast1/backups/ID --destination-database=restored-2026-09-15
```

Restores create a **new** database id; point a staging function set at it with `getFirestore("restored-2026-09-15")` to inspect, then export/import what you need. Verify flags against current gcloud docs — this surface changed several times in 2024–2025.

## Point-in-time recovery (PITR)

```sh
gcloud firestore databases update --database='(default)' --enable-pitr --project=snaptool-prod
```

- Keeps 7 days of versions; read any past state with a stale read: `db.collection("users").get()` at a `readTime` (Admin SDK: `query.get()` does not take it directly — use `db.runTransaction(…, { readOnly: true, readTime: Timestamp })` — verify against firebase docs for the exact API in your admin version) or export at a `--snapshot-time`.
- Restoring after a bad deploy or a runaway script: export at the timestamp before the incident, import into the live database (overwrites), or into a new database and copy selectively. PITR does not undo Storage deletions.
- Costs extra storage for versions; enable it on prod regardless.

## Environment cloning

`gcloud firestore export` from prod → `import` into a scrubbed staging project is the way to get realistic data; **scrub PII before or right after import** with a backfill script (replace emails, names, OCR text). Never import prod into a project developers use with real credentials on their phones.

## Runbook checklist for a destructive operation

1. Announce; pick a low-traffic window (03:00 Asia/Ho_Chi_Minh).
2. Take an export or confirm PITR is on and note the timestamp.
3. Dry-run the script on dev with prod-shaped data; then on staging.
4. Run on prod with `--apply`; watch Error Reporting and trigger invocation counts.
5. Verify with `count()` queries; sample documents.
6. Remove temporary markers (`_backfill`) and temporary trigger guards; redeploy.
7. Record what ran, on which commit, and the before/after counts in `_meta/migrations/{name}`.

## Does not exist / common mistakes

- `db.collection("x").delete()` — no such method; `recursiveDelete(ref)` or paged BulkWriter deletes.
- `recursiveDelete(query)` — takes a `DocumentReference` or `CollectionReference`, not a query.
- Running a backfill via `Promise.all(docs.map((d) => d.ref.update(...)))` on 100 k docs — unbounded concurrency, quota errors, memory; BulkWriter.
- Backfilling without a `where` on the migrated marker — the re-run touches everything again and fires all triggers again.
- Assuming exports are consistent snapshots to the millisecond — exports are point-in-time only with PITR/`--snapshot-time`; otherwise documents written during the export may or may not be included.
- Importing a partial export (`--collection-ids`) that was created without that flag — import requires the export to have been made with `--collection-ids` for subset imports.
- Treating scheduled backups as a replacement for exports — backups restore only into a new database in the same project; exports move across projects.
- Trusting the Firestore console "delete collection" for prod cleanup — it is a client-side paged delete that can time out half-way and fires triggers with no marker; use a script.

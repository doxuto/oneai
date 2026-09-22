# Storage triggers

Targets firebase-functions 6.x (`firebase-functions/v2/storage`), firebase-admin 13.x (`firebase-admin/storage`), `sharp` for image work.

## APIs

```ts
import { onObjectFinalized, onObjectDeleted, onObjectArchived, onObjectMetadataUpdated, type StorageEvent } from "firebase-functions/v2/storage";

export const onScanPageUploaded = onObjectFinalized(
  {
    bucket: "snaptool-prod.appspot.com",   // omit for the project's default bucket; one bucket per trigger
    region: "asia-southeast1",             // must be a region that can receive the bucket's events (bucket location or a supported dual/multi region mapping)
    memory: "1GiB",                        // sharp needs headroom; 256MiB OOMs on large photos
    timeoutSeconds: 120,
    maxInstances: 10,
    retry: false,
  },
  async (event: StorageEvent) => {
    const o = event.data;                  // StorageObjectData
    o.bucket; o.name;                      // "users/u1/scans/s1/page-1.jpg"
    o.contentType;                         // client-declared; may be undefined
    o.size;                                // string in the CloudEvent payload — Number(o.size)
    o.generation; o.metageneration;        // new generation per overwrite; metageneration per metadata change
    o.metadata;                            // custom metadata map (from the client's StorageMetadata.customMetadata)
    o.md5Hash; o.crc32c; o.timeCreated; o.updated;
    event.id; event.time;                  // idempotency key + commit time
  },
);
```

- `onObjectFinalized` fires when a new object **or a new generation** of an existing object is fully written (uploads, overwrites, copies). It does not fire for metadata-only updates (that is `onObjectMetadataUpdated`) or for deletes.
- Resumable uploads from iOS fire once, on completion.
- `event.data.name` is the full object key. Storage has no folders; `users/u1/` is a prefix.

## Path parsing and authorization

The path is your only reliable authorization input; the custom metadata and `contentType` are client-supplied.

```ts
const SCAN_PAGE = /^users\/([^/]+)\/scans\/([^/]+)\/page-(\d{1,3})\.(jpg|jpeg|png|heic|pdf)$/;

function parseScanPage(name: string): { uid: string; scanId: string; pageIndex: number; ext: string } | undefined {
  const m = SCAN_PAGE.exec(name);
  if (!m) return undefined;
  return { uid: m[1], scanId: m[2], pageIndex: Number(m[3]), ext: m[4] };
}
```

Mirror the regex in `storage.rules` (`fileName.matches(...)`) so the trigger never sees an unexpected shape. Return early for anything that does not match — the same bucket carries avatars, exports, and derived files.

## Guards

```ts
const parsed = parseScanPage(o.name);
if (!parsed) return;                                                       // not ours
if (!o.contentType?.startsWith("image/") && o.contentType !== "application/pdf") { logger.warn("bad contentType", { name: o.name, contentType: o.contentType }); return; }
if (Number(o.size) > 25 * 1024 * 1024) { logger.warn("too large", { name: o.name, size: o.size }); return; }   // rules already cap; belt and braces
if (o.metadata?.["source"] === "derived") return;                          // written by us
```

`contentType` is not proof. For images let `sharp` fail on non-image bytes (`sharp(buffer).metadata()` throws) and treat that as a permanent failure; for PDFs check the `%PDF-` magic prefix. Never pass an unchecked upload straight into a paid model call.

## Avoiding re-trigger

A trigger that writes back into the prefix it listens to fires itself. The rule is **derived output goes to a different prefix** the trigger's path regex rejects:

```
users/{uid}/scans/{scanId}/page-1.jpg          ← input (client writes, trigger listens)
derived/{uid}/scans/{scanId}/page-1.thumb.jpg   ← output (function writes, trigger ignores; rules: owner read, no client write)
derived/{uid}/scans/{scanId}/page-1.ocr.json
```

If a design forces output into the same prefix, set custom metadata `{ source: "derived" }` on the output and return early on it — but the invocation is still billed and the loop risk remains if the metadata is ever dropped. Prefix separation is the safe answer. Never overwrite the source object (new generation → new event → your own trigger again).

## Resize with `sharp`

```ts
import { onObjectFinalized } from "firebase-functions/v2/storage";
import { getStorage } from "firebase-admin/storage";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getFunctions } from "firebase-admin/functions";
import { logger } from "firebase-functions/logger";
import { claim } from "../lib/ledger";

const db = getFirestore();

export const onScanPageUploaded = onObjectFinalized(
  { region: "asia-southeast1", memory: "1GiB", timeoutSeconds: 120, maxInstances: 10 },
  async (event) => {
    const o = event.data;
    const parsed = parseScanPage(o.name);
    if (!parsed || !o.contentType?.startsWith("image/")) return;
    const { uid, scanId, pageIndex } = parsed;
    // Idempotency: generation changes on overwrite, so key on it rather than on event.id alone
    if (!(await claim(`scanPage:${o.bucket}/${o.name}#${o.generation}`))) return;

    const sharp = (await import("sharp")).default;                 // lazy: keeps cold start of other functions in this codebase small
    const bucket = getStorage().bucket(o.bucket);
    const [buffer] = await bucket.file(o.name).download();          // < 25 MiB by rules; for bigger use streams

    let meta;
    try { meta = await sharp(buffer).metadata(); }
    catch { await markPage(uid, scanId, pageIndex, "failed", "unsupported-image"); return; }   // permanent

    const thumb = await sharp(buffer).rotate().resize({ width: 400, withoutEnlargement: true }).jpeg({ quality: 80 }).toBuffer();
    const ocrInput = await sharp(buffer).rotate().resize({ width: 1600, withoutEnlargement: true }).jpeg({ quality: 85 }).toBuffer();

    const base = `derived/${uid}/scans/${scanId}/page-${pageIndex}`;
    await Promise.all([
      bucket.file(`${base}.thumb.jpg`).save(thumb, { contentType: "image/jpeg", metadata: { metadata: { source: "derived", ownerUid: uid } }, resumable: false }),
      bucket.file(`${base}.ocr.jpg`).save(ocrInput, { contentType: "image/jpeg", metadata: { metadata: { source: "derived", ownerUid: uid } }, resumable: false }),
    ]);

    await db.doc(`users/${uid}/scans/${scanId}/pages/${pageIndex}`).set({
      status: "queued", width: meta.width ?? null, height: meta.height ?? null,
      sourcePath: o.name, thumbPath: `${base}.thumb.jpg`, ocrInputPath: `${base}.ocr.jpg`,
      updatedAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    // Hand the expensive part to a task queue (retries, rate limits, longer deadline)
    await getFunctions().taskQueue("ocrPage").enqueue({ uid, scanId, pageIndex, objectPath: `${base}.ocr.jpg` }, { dispatchDeadlineSeconds: 300 });
    logger.info("scan page prepared", { uid, scanId, pageIndex, bytes: Number(o.size) });
  },
);
```

Notes:

- `sharp` ships native binaries; add it to `package.json` dependencies (not devDependencies). It builds fine for Node 22 on the Cloud Functions Linux x64 runtime. For HEIC input `sharp`'s bundled libvips needs HEIF support — verify the current `sharp` build supports HEIC decoding before promising it; safer to have the iOS app upload JPEG (convert with `UIImage.jpegData` / `CIContext`).
- `.rotate()` with no args applies EXIF orientation — iPhone photos are usually stored rotated with an EXIF flag; without this, thumbnails come out sideways.
- `resumable: false` on `save` for buffers < ~10 MB avoids the extra round trips of a resumable session.
- For files > ~50 MB use streams (`file.createReadStream().pipe(sharp()).pipe(file.createWriteStream())`) rather than buffers, and raise `memory`.
- Do the OCR/LLM call in the task worker, not here: storage triggers have a 540 s cap, no rate limits, and no backoff; the task queue has all three.

## Metadata

- Read custom metadata from `event.data.metadata` (a `Record<string, string>`). Treat as untrusted input; the rules allow-list its keys.
- Write custom metadata on derived files via the nested `metadata: { metadata: { … } }` shape of `@google-cloud/storage` (the outer `metadata` is the object's GCS metadata, the inner one is the custom map).
- Set `cacheControl: "private, max-age=3600"` on derived images if the app fetches them through download URLs; leave default for SDK reads.
- Do not store authorization data in metadata; the path carries the uid.

## Deletion cascade

```ts
export const onScanPageDeleted = onObjectDeleted({ region: "asia-southeast1", maxInstances: 5 }, async (event) => {
  const parsed = parseScanPage(event.data.name);
  if (!parsed) return;
  const { uid, scanId, pageIndex } = parsed;
  const base = `derived/${uid}/scans/${scanId}/page-${pageIndex}`;
  await getStorage().bucket(event.data.bucket).deleteFiles({ prefix: base, force: true });   // ignores not-found
  await db.doc(`users/${uid}/scans/${scanId}/pages/${pageIndex}`).delete();                  // idempotent
});
```

`onObjectDeleted` fires for explicit deletes and lifecycle-rule deletes, and for overwrites only when versioning is on (then the old generation is "archived", not deleted — `onObjectArchived`). With `deleteAccount` doing `bucket.deleteFiles({ prefix: "users/{uid}/" })`, this trigger runs once per object — keep it cheap.

## Region

The trigger region must be able to receive events from the bucket: same region as the bucket, or for multi-region buckets (`US`, `EU`, `ASIA`) a region inside it that Eventarc supports. Default bucket location = the project's default GCP resource location, chosen at project creation; if it is `US` and your functions are `asia-southeast1`, either create a regional bucket in `asia-southeast1` for uploads (and point the iOS app at it via `Storage.storage(url: "gs://…")`) or deploy the storage trigger in `us-central1`. Check with `gsutil ls -L -b gs://<bucket>` → `Location constraint`.

## Testing

`firebase-functions-test` 3.x: build a `StorageEvent` by hand (`{ data: { bucket, name, contentType, size: "1234", generation: "1", metadata: {} }, id: "evt-1", time: new Date().toISOString() }`) and call the wrapped handler; mock `getStorage` or run against the Storage emulator (`FIREBASE_STORAGE_EMULATOR_HOST`), which **does** fire `onObjectFinalized` locally for uploads through the SDK. Assert derived objects and the Firestore page doc; invoke twice to prove idempotency.

## Does not exist / common mistakes

- `functions.storage.object().onFinalize((object) => …)` — v1. v2 is `onObjectFinalized(options, (event) => …)` with `event.data`.
- `event.data.size` as a number — it is a string; `Number()` it.
- Writing the thumbnail next to the source under `users/{uid}/…` — re-triggers; use `derived/`.
- Overwriting the source with a resized version — new generation, new event, infinite loop.
- Trusting `contentType` or the file extension — sniff or let `sharp` reject.
- Doing OCR/Gemini inline in the storage trigger — no retries, no rate limit, 540 s cap; enqueue.
- `import sharp from "sharp"` at the top of a module that also exports light functions — every cold start pays for libvips; lazy-import or split codebases.
- `memory: "256MiB"` with `sharp` on 12-megapixel photos — OOM; 1 GiB.
- Assuming the trigger fires for the emulator's REST uploads or `gsutil cp` to the emulator — only SDK/emulator-API uploads fire locally; verify with the current firebase-tools.
- Wildcards in `bucket` or path filters — the trigger is per bucket; path filtering is your regex.

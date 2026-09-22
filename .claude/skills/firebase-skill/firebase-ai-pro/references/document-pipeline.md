# Document pipeline (SnapTool-style)

Scan → upload → OCR/extract → result in the app. The work takes seconds to a minute, so it never runs inside a callable. The shape:

```
iOS                         Storage                   Functions                          Firestore
────                        ───────                   ─────────                          ─────────
1. write scan doc ─────────────────────────────────────────────────────────────────────▶ users/{uid}/scans/{scanId}
   { status: "uploading", pageCount: 2 }
2. upload page-1.jpg ─────▶ users/{uid}/scans/{scanId}/page-1.jpg
                                        └──▶ onObjectFinalized ──▶ tx: pages.1 = path ─▶ (status stays "uploading")
3. upload page-2.jpg ─────▶ …/page-2.jpg
                                        └──▶ onObjectFinalized ──▶ tx: pages.2 = path, all pages present
                                                                    → status "queued" + enqueue task
                                                          processScan (task) ──▶ status "processing"
                                                            download → sharp → Gemini/Vision → validate
                                                                                 ──▶ status "done" | "failed"
4. snapshot listener on the scan doc ◀───────────────────────────────────────────── renders each transition
```

## Firestore document

```
users/{uid}/scans/{scanId}
  status:      "uploading" | "queued" | "processing" | "done" | "failed"
  pageCount:   number                 // set by the client before uploading
  pages:       { "1": "users/u/scans/s/page-1.jpg", "2": "…" }   // filled by the Storage trigger
  kind:        "receipt" | "invoice" | "note" | "unknown"          // classification result
  ocrText:     string                 // full text, ≤ 100 KB; larger → Storage file + ocrTextPath
  extracted:   object | null          // zod-validated structured result (structured-output.md)
  error:       { code: string, message: string } | null            // user-presentable
  attempts:    number
  model:       string                 // "gemini-2.5-flash" — for later evals
  usage:       { prompt: number, output: number, total: number }
  createdAt, updatedAt: Timestamp
  expiresAt:   Timestamp              // TTL policy → auto-delete scans after 30 days if the product allows
```

Rules: the owner may create the doc with `status: "uploading"` and `pageCount`, and may read it; every other transition is server-only.

```
match /users/{uid}/scans/{scanId} {
  allow read: if isOwner(uid);
  allow create: if isOwner(uid)
    && request.resource.data.status == 'uploading'
    && request.resource.data.pageCount is int && request.resource.data.pageCount >= 1 && request.resource.data.pageCount <= 20
    && request.resource.data.keys().hasOnly(['status','pageCount','createdAt']);
  allow update, delete: if false;
}
```

Storage rules: `match /users/{uid}/scans/{scanId}/{file}` — owner write, `request.resource.size < 10 * 1024 * 1024`, `contentType.matches('image/.*')`.

## iOS: upload

```swift
// 1. create the scan doc (server assigns nothing; scanId is a client UUID so uploads can reference it)
let scanId = uuid().uuidString.lowercased()
try await db.document("users/\(uid)/scans/\(scanId)").setData([
  "status": "uploading", "pageCount": pages.count, "createdAt": FieldValue.serverTimestamp(),
])
// 2. upload pages — resize on device first (≤ 2000 px, JPEG 0.8) so the upload is small and the server does less
for (index, image) in pages.enumerated() {
  let data = image.jpegData(compressionQuality: 0.8)!          // after a UIGraphicsImageRenderer downscale
  let ref = Storage.storage().reference(withPath: "users/\(uid)/scans/\(scanId)/page-\(index + 1).jpg")
  let meta = StorageMetadata()
  meta.contentType = "image/jpeg"
  meta.customMetadata = ["scanId": scanId, "page": String(index + 1)]
  _ = try await ref.putDataAsync(data, metadata: meta)
}
```

Wrap the two steps in a `@DependencyClient` (`ScanClient.upload`) and drive from a reducer effect (`tca-pro`); image downscaling before upload belongs in the client too — a 12 MP HEIC is 4–6 MB, a 2000 px JPEG is ~500 KB.

## Storage trigger: record the page, enqueue once

```ts
import { onObjectFinalized } from "firebase-functions/v2/storage";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getFunctions } from "firebase-admin/functions";
import { logger } from "firebase-functions";

const db = getFirestore();
const PATH = /^users\/([^/]+)\/scans\/([^/]+)\/page-(\d+)\.jpg$/;

export const onScanPageUploaded = onObjectFinalized(
  { region: "asia-southeast1", memory: "256MiB" },                // bucket defaults to the project's default bucket
  async (event) => {
    const m = PATH.exec(event.data.name);
    if (!m) return;                                                 // not a scan page
    const [, uid, scanId, page] = m;
    if (!event.data.contentType?.startsWith("image/")) return;
    if (Number(event.data.size) > 10 * 1024 * 1024) { logger.warn("page too large", { uid, scanId, page }); return; }

    const ref = db.doc(`users/${uid}/scans/${scanId}`);
    const shouldEnqueue = await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) return false;                               // orphan upload; the prune job removes the file
      const data = snap.data()!;
      if (data.status !== "uploading") return false;                // already queued/processed — idempotent on re-delivery
      const pages = { ...(data.pages ?? {}), [page]: event.data.name };
      const complete = Object.keys(pages).length >= Number(data.pageCount);
      tx.update(ref, { pages, updatedAt: FieldValue.serverTimestamp(), ...(complete ? { status: "queued" } : {}) });
      return complete;
    });

    if (shouldEnqueue) {
      await getFunctions().taskQueue("locations/asia-southeast1/functions/processScan")
        .enqueue({ uid, scanId }, { dispatchDeadlineSeconds: 600 });
      logger.info("scan queued", { uid, scanId });
    }
  }
);
```

The transaction is the idempotency point: a redelivered Storage event or a duplicate page upload can never enqueue twice because the `"uploading" → "queued"` transition happens exactly once. The task queue is the retry point: the trigger itself stays under a second.

## Worker: `onTaskDispatched`

```ts
import { onTaskDispatched } from "firebase-functions/v2/tasks";
import { getStorage } from "firebase-admin/storage";
import { defineSecret } from "firebase-functions/params";
import { GoogleGenAI, createPartFromBase64 } from "@google/genai";
import sharp from "sharp";

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

export const processScan = onTaskDispatched(
  {
    region: "asia-southeast1",
    secrets: [GEMINI_API_KEY],
    memory: "1GiB",                       // sharp + several pages in memory
    timeoutSeconds: 540,
    retryConfig: { maxAttempts: 4, minBackoffSeconds: 20, maxDoublings: 3 },
    rateLimits: { maxConcurrentDispatches: 5, maxDispatchesPerSecond: 2 },   // also caps Gemini QPS
  },
  async (req) => {
    const { uid, scanId } = req.data as { uid: string; scanId: string };
    const ref = db.doc(`users/${uid}/scans/${scanId}`);
    const snap = await ref.get();
    if (!snap.exists) return;
    const scan = snap.data()!;
    if (scan.status === "done") return;                              // idempotent: task redelivered after success
    if (scan.status === "failed" && scan.error?.code !== "transient") return;

    await ref.update({ status: "processing", attempts: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() });
    try {
      const bucket = getStorage().bucket();
      const pageKeys = Object.keys(scan.pages).sort((a, b) => Number(a) - Number(b)).slice(0, 20);
      const parts = [];
      for (const key of pageKeys) {
        const [raw] = await bucket.file(scan.pages[key] as string).download();
        const jpeg = await sharp(raw).rotate().resize({ width: 1600, height: 1600, fit: "inside", withoutEnlargement: true })
          .jpeg({ quality: 80 }).toBuffer();
        parts.push({ text: `Page ${key}:` }, createPartFromBase64(jpeg.toString("base64"), "image/jpeg"));
      }

      const ai = new GoogleGenAI({ apiKey: GEMINI_API_KEY.value() });
      const result = await generateStructured({                     // structured-output.md
        ai, model: "gemini-2.5-flash", schema: ScanResult, feature: "processScan", uid,
        system: SCAN_SYSTEM, parts: [...parts, { text: "Transcribe all text (ocrText), classify (kind), and extract fields." }],
        maxOutputTokens: 8192,
      });

      await ref.update({
        status: "done", kind: result.kind, ocrText: result.ocrText.slice(0, 100_000), extracted: result.extracted,
        error: null, model: "gemini-2.5-flash", updatedAt: FieldValue.serverTimestamp(),
      });
    } catch (e: unknown) {
      const transient = isTransient(e);                               // 429/5xx/timeout → let Cloud Tasks retry
      await ref.update({
        status: "failed",
        error: transient ? { code: "transient", message: "Processing is taking longer than usual" }
                         : { code: "unreadable", message: "We could not read this document" },
        updatedAt: FieldValue.serverTimestamp(),
      });
      logger.error("processScan failed", { uid, scanId, transient, error: String(e) });
      if (transient) throw e;                                         // non-2xx → Cloud Tasks retries per retryConfig
    }
  }
);
```

`ScanResult` combines `ocrText: z.string()`, `kind: z.enum([...])`, and `extracted: Receipt.nullable()` from `structured-output.md`. One model call does OCR, classification, and extraction for a receipt-sized document; split into two calls (classify with flash-lite, then extract with the kind-specific schema) once the schema union grows.

Failure states the client must render: `failed/unreadable` (final; offer retake), `failed/transient` (will retry; show progress), `failed/quota` (set before enqueue when the user's daily limit is hit — `cost-and-limits.md`), plus a watchdog: a scheduled job that marks `processing` documents older than 15 minutes as `failed/transient` and re-enqueues once.

## Cloud Vision vs Gemini

| | Cloud Vision `documentTextDetection` | Gemini multimodal |
|---|---|---|
| Output | text + per-word bounding boxes + confidence + language | text you asked for, in the shape you asked for |
| Structured extraction | no — you parse the text afterwards | yes, in the same call |
| Handwriting, Vietnamese diacritics | good; deterministic | good; can normalise/correct, can also hallucinate |
| Layout (tables, columns) | boxes let you rebuild layout exactly | reads layout semantically; no coordinates |
| Cost | per image | per token (image ≈ fixed tokens per tile + output) |
| Latency | ~1–2 s/page | 3–15 s depending on output length |
| Use when | you need coordinates (highlight on the image), or exact transcription with confidence | you need fields, classification, translation, or summary |

Combining both is legitimate: Vision for `ocrText` + boxes, Gemini with that text (not the image) for extraction — cheaper per page and Gemini gets clean input. Cloud Vision needs the Vision API enabled; the function's service account uses ADC.

```ts
import { ImageAnnotatorClient } from "@google-cloud/vision";
const vision = new ImageAnnotatorClient();
const [res] = await vision.documentTextDetection({ image: { content: jpeg }, imageContext: { languageHints: ["vi", "en"] } });
const text = res.fullTextAnnotation?.text ?? "";
const lowConfidence = (res.fullTextAnnotation?.pages ?? []).some((p) => (p.confidence ?? 1) < 0.6);
```

## iOS: listen

```swift
@DependencyClient
struct ScanClient: Sendable {
  var observe: @Sendable (_ scanId: String) -> AsyncThrowingStream<Scan, any Error> = { _ in .finished() }
}
// live: wrap addSnapshotListener in AsyncThrowingStream; remove the listener in onTermination.
// Scan: Codable mirror of the document (status as a String enum with an `unknown` fallback).
```

Reducer: `.run { for try await scan in scanClient.observe(id) { await send(.scanUpdated(scan)) } }.cancellable(id:)` started right after the upload effect succeeds; the view shows a per-status state. Never poll a callable; never wait on the upload effect for the result.

## Housekeeping

- Orphaned files (doc missing, upload finished): nightly `onSchedule` lists `users/*/scans/*` older than a day whose doc does not exist and deletes them — or set a Storage lifecycle rule to delete `page-*.jpg` after 30 days and rely on the Firestore TTL for the doc.
- Storing the resized JPEG back (`…/page-1.small.jpg`) lets the NSE/app show a thumbnail and lets a retry skip `sharp`; optional.
- Large `ocrText` (> 100 KB) goes to `…/ocr.txt` in Storage with `ocrTextPath` on the doc; Firestore documents cap at 1 MiB.

## Does not exist / common mistakes

- Doing OCR inside `onObjectFinalized` — 60 s default timeout, no rate limiting, retries re-run the whole thing. Enqueue.
- `getFunctions().taskQueue("processScan")` for a function outside `us-central1` — use the `locations/{region}/functions/{name}` form.
- Enqueuing from the client — Cloud Tasks enqueue is Admin-only; the client writes Firestore and the server enqueues.
- Storage trigger on a bucket in another region than the function — deploy fails or the trigger never fires; match regions.
- Reading `event.data.metadata.scanId` as the only source of `scanId` — custom metadata is client-controlled; derive uid/scanId from the object path (which rules enforce) and only cross-check metadata.
- `status: "processing"` without a watchdog — a crashed instance leaves the scan spinning forever in the app.
- Throwing from the worker on a permanent failure — Cloud Tasks retries a document that will never parse; return normally after writing `failed/unreadable`.
- Sending the original HEIC/12 MP image to Gemini — convert and downscale; HEIC support varies and tokens scale with tiles.

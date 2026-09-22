# Task queues

Targets firebase-functions 6.x (`firebase-functions/v2/tasks`), firebase-admin 13.x (`firebase-admin/functions`). Backed by Cloud Tasks; the Cloud Tasks API must be enabled in the project (the CLI prompts on first deploy). The function's service account needs `cloudtasks.enqueuer` to enqueue and the worker is invoked with an OIDC token — the CLI configures both for same-project use.

## When

Use a task queue for any work that is: slower than a user should wait for, retried on failure, rate-limited against an upstream (Gemini, APNs, a partner API), fanned out per item, or scheduled for later (`scheduleDelaySeconds`). Callables and triggers **enqueue and return**; workers do the work; the iOS app watches a status document.

Do not use a task queue for: work under ~1 s with no upstream (do it inline), strictly ordered processing (Cloud Tasks does not order), or exactly-once semantics (does not exist; see `idempotency.md`).

## Worker

```ts
import { onTaskDispatched, type Request as TaskRequest } from "firebase-functions/v2/tasks";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/logger";
import { z } from "zod";

const db = getFirestore();
const OcrTask = z.object({ uid: z.string(), scanId: z.string(), pageIndex: z.number().int().min(0), objectPath: z.string() });
export type OcrTask = z.infer<typeof OcrTask>;

export const ocrPage = onTaskDispatched(
  {
    region: "asia-southeast1",
    retryConfig: {
      maxAttempts: 5,              // total attempts including the first; -1 = unlimited (never)
      minBackoffSeconds: 10,
      maxBackoffSeconds: 300,
      maxDoublings: 4,
      maxRetrySeconds: 3600,       // give up after 1 h regardless of attempts
    },
    rateLimits: {
      maxConcurrentDispatches: 6,  // parallel workers — match the upstream's concurrency budget
      maxDispatchesPerSecond: 2,   // sustained rate
    },
    timeoutSeconds: 300,
    memory: "1GiB",
    maxInstances: 6,
    secrets: [GEMINI_API_KEY],
  },
  async (req: TaskRequest<OcrTask>) => {
    const task = OcrTask.parse(req.data);           // throw → retry; for poison payloads catch and mark failed instead
    req.headers;                                    // includes x-cloudtasks-taskretrycount, x-cloudtasks-taskexecutioncount
    const attempt = Number(req.headers["x-cloudtasks-taskretrycount"] ?? 0);
    const scanRef = db.doc(`users/${task.uid}/scans/${task.scanId}`);
    const pageRef = scanRef.collection("pages").doc(String(task.pageIndex));   // deterministic id → idempotent

    const existing = await pageRef.get();
    if (existing.get("status") === "done") return;  // already processed by an earlier attempt

    await pageRef.set({ status: "processing", attempt, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    try {
      const text = await runOcr(task.objectPath);   // Gemini / Vision call
      await pageRef.set({ status: "done", text, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    } catch (err) {
      const permanent = isPermanent(err);           // e.g. unsupported image, 4xx from upstream
      await pageRef.set({ status: permanent ? "failed" : "retrying", attempt,
        error: { code: permanent ? "unsupported" : "transient", message: "Could not read this page." },
        updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      logger.error("ocr page failed", { uid: task.uid, scanId: task.scanId, page: task.pageIndex, attempt, permanent, err: String(err) });
      if (!permanent) throw err;                    // non-2xx → Cloud Tasks retries with backoff
      // permanent: return normally so the task is acknowledged and not retried
    }
  },
);
```

Semantics:

- Returning normally = success (HTTP 2xx to Cloud Tasks). Throwing = failure → retry per `retryConfig`. After `maxAttempts` / `maxRetrySeconds` the task is dropped — there is no dead-letter queue in Cloud Tasks; record failures in Firestore yourself.
- `req.data` is the JSON payload from `enqueue`. Validate it; the payload format is your contract.
- Retry headers (`x-cloudtasks-taskretrycount`, `x-cloudtasks-taskexecutioncount`, `x-cloudtasks-tasketa`) are available on `req.headers` — verify exact names against Cloud Tasks docs; use them for attempt-aware logic, not for correctness.
- `rateLimits` and `retryConfig` are queue settings created at deploy; changing them requires a redeploy of that function.
- The dispatch deadline (per task, set at enqueue) must be ≥ the work duration and ≤ the function's `timeoutSeconds`; if the handler exceeds it, Cloud Tasks counts the attempt as failed even if the handler later finishes — then the retry duplicates work. Set both consistently.

## Enqueue

```ts
import { getFunctions } from "firebase-admin/functions";

const queue = getFunctions().taskQueue<OcrTask>("ocrPage");             // same project + region resolved automatically
// Different region: getFunctions().taskQueue("locations/asia-southeast1/functions/ocrPage")
// Other project or non-Firebase caller: needs the full function URI and IAM — see firebase docs.

await queue.enqueue(
  { uid, scanId, pageIndex: 0, objectPath },
  {
    scheduleDelaySeconds: 0,          // or scheduleTime: new Date(...) — run later
    dispatchDeadlineSeconds: 300,     // 15 s … 30 min; default 10 min
    id: `${scanId}-page-0`,           // optional task name for dedupe (Cloud Tasks rejects duplicate ids for ~1 h after completion) — verify field name against firebase docs; omit if unsure
    headers: { "x-trace": traceId },  // forwarded to req.headers
    uri: undefined,                   // override target — normally omitted
  },
);
```

Facts:

- `enqueue` from **inside** a function in the same project needs only the function name. From a local script or another project the SDK needs the function's URL and a service account with `run.invoker` + `cloudtasks.enqueuer`; do not design that path for the app — the iOS app never enqueues directly; it calls a callable that enqueues.
- Payload limit is 100 KB (Cloud Tasks). Pass ids and paths, not file contents.
- Enqueue is not transactional with Firestore. Order: write the status doc (`queued`) **then** enqueue; if the enqueue fails, the doc says `queued` forever — a scheduled sweeper re-enqueues docs stuck in `queued` for > N minutes. If you enqueue first and the doc write fails, the worker runs against a missing doc — make the worker create it with `set({ merge: true })`.
- Enqueueing inside `runTransaction` runs on every retry. Do it after.
- The emulator supports task queue functions: `enqueue` targets the emulator and the worker runs locally; retries/rate limits are approximated — verify against firebase docs for your firebase-tools version. Emulator enqueue endpoint exists for manual tests (`/functions/projects/{p}/locations/{l}/queues/{fn}/tasks`) — say "verify current docs" when quoting it.

## Fan-out pattern

Parent creates N child tasks; children update their own status doc; a completion is derived, not counted.

```ts
// Enqueue side (in a callable or trigger)
const scanRef = db.doc(`users/${uid}/scans/${scanId}`);
await scanRef.set({ status: "queued", pageCount: pages.length, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
await Promise.all(pages.map((p, i) => queue.enqueue({ uid, scanId, pageIndex: i, objectPath: p }, { dispatchDeadlineSeconds: 300 })));

// Completion: a trigger on users/{uid}/scans/{scanId}/pages/{pageIndex} checks whether all pages are done
export const onPageWritten = onDocumentWritten({ document: "users/{uid}/scans/{scanId}/pages/{pageIndex}", region: "asia-southeast1", maxInstances: 10 }, async (event) => {
  if (!event.data?.after.exists) return;
  if (event.data.before.get("status") === event.data.after.get("status")) return;   // loop guard
  const { uid, scanId } = event.params;
  const scanRef = db.doc(`users/${uid}/scans/${scanId}`);
  await db.runTransaction(async (tx) => {
    const scan = await tx.get(scanRef);
    const pages = await tx.get(scanRef.collection("pages").select("status"));
    const total = scan.get("pageCount") as number;
    const done = pages.docs.filter((d) => d.get("status") === "done").length;
    const failed = pages.docs.filter((d) => d.get("status") === "failed").length;
    const next = done === total ? "done" : failed > 0 && done + failed === total ? "failed" : "processing";
    if (scan.get("status") !== next) tx.update(scanRef, { status: next, doneCount: done, updatedAt: FieldValue.serverTimestamp() });
  });
});
```

Deriving completion from child docs (instead of `increment`-ing a counter from each worker) survives duplicate worker runs. For large N (> 100 pages) keep a counter with `increment` guarded by a per-page ledger instead of re-reading all pages.

## Status documents for the client

The iOS app listens to `users/{uid}/scans/{scanId}`:

```swift
struct Scan: Codable, Equatable {
  enum Status: String, Codable { case uploading, queued, processing, done, failed }
  @DocumentID var id: String?
  var status: Status
  var pageCount: Int
  var doneCount: Int?
  var error: ScanError?
}
struct ScanError: Codable, Equatable { let code: String; let message: String }
```

Rules: owner read, no client write (server-only). Fields: `status` (enum string), progress (`doneCount/pageCount`), `error` with a client-safe message, `updatedAt`. Never write the raw upstream error or the task payload into it. The TCA feature turns the stream into `.scanUpdated(Scan)` actions; the "Retry" button calls a callable that re-enqueues, not the queue directly.

## Throttling an upstream

`maxConcurrentDispatches` × (per-call latency) ≈ throughput; `maxDispatchesPerSecond` caps burst. For Gemini with a 60 RPM limit: `maxDispatchesPerSecond: 1`, `maxConcurrentDispatches: 4`. For APNs fan-out via FCM: high concurrency is fine (`sendEachForMulticast` handles 500 tokens per call); chunk recipients per task. One queue per upstream — a shared worker for OCR and push would let one starve the other.

## Does not exist / common mistakes

- `functions.tasks.taskQueue({...}).onDispatch(...)` — v1. v2 is `onTaskDispatched(options, handler)`.
- Enqueue from the iOS app — there is no client SDK for Cloud Tasks; go through a callable.
- Treating `maxAttempts` as "exactly N tries and then a dead-letter" — there is no DLQ; persist failures yourself.
- Counting completions with `increment` from workers without a ledger — retried workers over-count.
- Throwing on permanent input errors — retries until `maxAttempts`; catch, mark `failed`, return.
- `dispatchDeadlineSeconds` shorter than the work — Cloud Tasks retries a still-running task.
- Payloads with image bytes — 100 KB limit; pass Storage paths.
- Using a task's `scheduleDelaySeconds` as a cron — one-shot delay only; recurring = `onSchedule`.
- `rateLimits` on `onCall` / `onRequest` — task-queue only.

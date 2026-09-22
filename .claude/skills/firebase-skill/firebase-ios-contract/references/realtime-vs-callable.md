# Realtime vs callable

Two transports, two jobs:

- **Callable** — request/response. The client asks, waits a few seconds, gets an answer or an error. Auth, App Check, validation, and error mapping are built in.
- **Firestore listener** — the client observes a document; the server writes to it whenever it likes. No request, no timeout, survives app backgrounding, resumes on reconnect.

Pick by duration and shape, not by habit.

## Decision table

| Situation | Use | Why |
|---|---|---|
| Create/update/delete with a result the UI needs now (< 5 s) | Callable | Simplest; error is the answer |
| Read a single document the user owns | Firestore read/listener via rules | No function needed; rules enforce ownership |
| Read that needs server-side joins, secrets, or cross-user data | Callable | Rules cannot express it |
| Work that takes > 10 s (OCR, AI over a document, export) | Callable to **start** → task queue → status doc → listener | Callable timeouts, client timeouts, backgrounding |
| Work that reports progress (page 3 of 12) | Same | Progress is a series of writes |
| Work triggered by an upload | `onObjectFinalized` → task → status doc → listener | No callable at all; the upload is the request |
| Live collaborative data, presence, chat history | Listener | Server pushes; client never polls |
| Token-by-token AI reply the user is watching | Streaming callable (`stream()`) | Short-lived, foreground, one consumer |
| AI reply that must survive the user backgrounding the app | Task + status doc with partial `text` field | Streaming callable dies with the app |
| Polling a callable every N seconds | Never | Cost, latency, battery — use a listener |

## The status-document pattern

Three parts: a callable that enqueues, a task worker that does the work and writes status, and a listener on the client.

### 1. Callable enqueues and returns a job id

```ts
// functions/src/scans/startScan.ts
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFunctions } from "firebase-admin/functions";
import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import { db } from "../lib/admin.js";
import { parse } from "../lib/validate.js";

const StartScanInput = z.object({
  client: ClientInfo,
  storagePath: z.string().regex(/^users\/[^/]+\/scans\/[^/]+\/page-\d+\.jpg$/),
});

export interface StartScanOutput { jobId: string }

export const startScan = onCall({ enforceAppCheck: true, timeoutSeconds: 15 }, async (request): Promise<StartScanOutput> => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required");
  const uid = request.auth.uid;
  const { storagePath } = parse(StartScanInput, request.data);
  if (!storagePath.startsWith(`users/${uid}/`)) throw new HttpsError("permission-denied", "Not your file");

  const jobRef = db.collection(`users/${uid}/jobs`).doc();
  await jobRef.set({
    type: "scan",
    status: "queued",
    progress: 0,
    input: { storagePath },
    result: null,
    error: null,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });

  await getFunctions().taskQueue("processScan").enqueue(
    { uid, jobId: jobRef.id },
    { dispatchDeadlineSeconds: 60 * 10 },
  );
  return { jobId: jobRef.id };
});
```

The callable returns in well under a second. The job document is the contract from here on.

### 2. Task worker writes status

```ts
// functions/src/scans/processScan.ts
import { onTaskDispatched } from "firebase-functions/v2/tasks";
import { FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/logger";
import { db } from "../lib/admin.js";

interface Payload { uid: string; jobId: string }

export const processScan = onTaskDispatched<Payload>(
  {
    retryConfig: { maxAttempts: 3, minBackoffSeconds: 10 },
    rateLimits: { maxConcurrentDispatches: 6 },
    memory: "1GiB", cpu: 1, timeoutSeconds: 540, secrets: [GEMINI_API_KEY],
  },
  async (req) => {
    const { uid, jobId } = req.data;
    const jobRef = db.doc(`users/${uid}/jobs/${jobId}`);
    const job = await jobRef.get();
    if (!job.exists || job.get("status") === "done") return;   // idempotent on retry

    await jobRef.update({ status: "processing", progress: 0, updatedAt: FieldValue.serverTimestamp() });
    try {
      const pages = await listPages(job.get("input.storagePath"));
      let text = "";
      for (const [i, page] of pages.entries()) {
        text += await ocrPage(page);
        await jobRef.update({ progress: Math.round(((i + 1) / pages.length) * 100), updatedAt: FieldValue.serverTimestamp() });
      }
      await jobRef.update({
        status: "done", progress: 100,
        result: { type: "ocr", text, pageCount: pages.length },
        updatedAt: FieldValue.serverTimestamp(),
      });
    } catch (err) {
      const permanent = isPermanent(err);
      logger.error("scan.failed", { uid, jobId, permanent, error: String(err) });
      await jobRef.update({
        status: permanent ? "failed" : "queued",
        error: { code: permanent ? "invalidInput" : "transient", message: "Could not process scan" },
        updatedAt: FieldValue.serverTimestamp(),
      });
      if (!permanent) throw err;   // rethrow → Cloud Tasks retries; permanent → return, no retry
    }
  },
);
```

Status document shape (the contract; mirror it in Swift):

```ts
interface JobDoc {
  type: "scan" | "summary";
  status: "queued" | "processing" | "done" | "failed";
  progress: number;                       // 0–100
  input: Record<string, unknown>;
  result: JobResult | null;               // discriminated union, see shared-types.md
  error: { code: string; message: string } | null;
  createdAt: Timestamp; updatedAt: Timestamp;   // Firestore Timestamps are fine HERE — this is a document, not a callable response
}
```

Rules: `status` is the state machine; `progress` is cosmetic; `result` is set exactly once, with `status: "done"`; `error` mirrors the `HttpsError` code vocabulary so the client reuses `APIError` mapping. Firestore rules allow the owner to read `users/{uid}/jobs/{jobId}` and nobody to write it from the client.

### 3. Client listens

Wrap the listener in a dependency that returns an `AsyncStream`; the reducer consumes it in an effect (`tca-pro` → `references/effects.md`, long-living effects).

```swift
import ComposableArchitecture
import FirebaseFirestore

struct JobDoc: Codable, Equatable, Sendable {
  enum Status: String, Codable, Equatable, Sendable { case queued, processing, done, failed, unknown
    init(from decoder: Decoder) throws { self = Status(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown }
  }
  struct JobError: Codable, Equatable, Sendable { let code: String; let message: String }
  let status: Status
  let progress: Int
  let result: JobResult?
  let error: JobError?
  @ServerTimestamp var updatedAt: Date?     // Firestore Timestamp → Date via FirebaseFirestore's Codable support
}

@DependencyClient
struct JobsClient: Sendable {
  var observe: @Sendable (_ jobId: String) -> AsyncThrowingStream<JobDoc, Error> = { _ in .finished() }
}

extension JobsClient: DependencyKey {
  static let liveValue = JobsClient(
    observe: { jobId in
      AsyncThrowingStream { continuation in
        guard let uid = Auth.auth().currentUser?.uid else {
          continuation.finish(throwing: APIError(kind: .unauthenticated, details: nil, debugMessage: "no user")); return
        }
        let reg = Firestore.firestore().document("users/\(uid)/jobs/\(jobId)").addSnapshotListener { snap, error in
          if let error { continuation.finish(throwing: APIError(error)); return }
          guard let snap, snap.exists else { return }
          do { continuation.yield(try snap.data(as: JobDoc.self)) }
          catch { continuation.finish(throwing: APIError(kind: .decoding, details: nil, debugMessage: String(describing: error))) }
        }
        continuation.onTermination = { _ in reg.remove() }
      }
    }
  )
}
```

Reducer:

```swift
case .startScanButtonTapped:
  state.phase = .starting
  return .run { [path = state.storagePath] send in
    await send(.startScanResponse(Result { try await scansClient.startScan(StartScanRequest(storagePath: path)) }.mapError { $0 as? APIError ?? .unknown }))
  }

case let .startScanResponse(.success(response)):
  state.phase = .running(jobId: response.jobId, progress: 0)
  return .run { send in
    for try await job in jobsClient.observe(response.jobId) {
      await send(.jobUpdated(job))
    }
  } catch: { error, send in
    await send(.jobFailed(error as? APIError ?? .unknown))
  }
  .cancellable(id: CancelID.job, cancelInFlight: true)

case let .jobUpdated(job):
  switch job.status {
  case .queued, .processing, .unknown:
    state.phase = .running(jobId: state.jobId, progress: job.progress)
    return .none
  case .done:
    state.phase = .finished(job.result)
    return .cancel(id: CancelID.job)
  case .failed:
    state.phase = .failed(job.error)
    return .cancel(id: CancelID.job)
  }
```

- Cancel the listener when `status` reaches a terminal state and when the screen goes away.
- The listener delivers the current document immediately on attach, so a job that finished while the app was backgrounded is picked up on the next attach — no "did I miss it" logic.
- Firestore `snap.data(as:)` decodes `Timestamp` to `Date` natively; that is why status docs may keep `Timestamp` fields while callable responses may not.
- Test the reducer by overriding `jobsClient.observe` with a hand-built `AsyncThrowingStream` that yields `queued`, `processing`, `done` and asserting the phase transitions with `TestStore`.

## Combining: callable returns a snapshot, listener keeps it fresh

For lists the user edits (notes), do not route reads through callables at all: Firestore rules + a collection listener give offline cache, live updates, and no function cost. Callables are for writes with server logic (quota, validation, side effects) and for reads the rules cannot express. When a callable creates a document the client already observes, the listener delivers the new document; the callable response only needs the `id`.

## Anti-patterns

- **Polling a callable** (`getJobStatus` every 2 s) — pays for a function invocation and a Firestore read each tick, lags by the interval, drains battery. Listener.
- **Long callable that does the work inline** with `timeoutSeconds: 540` — the client default timeout is 70 s; the app may be backgrounded; a retry re-runs the whole job. Task + status doc.
- **Callable that returns the result AND writes a status doc** — two sources of truth; the client must reconcile. Pick one per operation.
- **Streaming callable for anything the user might background** — the stream dies with the connection; partial output is lost unless the server also persists it.
- **Client writes `status: "queued"` itself and a trigger picks it up** — works, but the client can now write arbitrary job docs; the callable + admin write keeps validation and quota server-side. Acceptable only for trusted, rules-validated shapes.
- **Listener on a collection with thousands of docs** — bandwidth and memory; paginate or listen to a summary doc the server maintains.

## Does not exist / common mistakes

- `functions.httpsCallable(...).stream()` on a non-`StreamResponse` callable — the response generic must be `StreamResponse<Message, Result>`.
- Expecting a callable to keep running after the client disconnects — Cloud Run may keep the instance briefly, but the response is lost; only a task or trigger is durable.
- Returning the job doc from `startScan` with `Timestamp` fields — the callable path forbids `Timestamp`; return `{ jobId }` and let the listener carry the rest.
- `addSnapshotListener` without `remove()` in `onTermination` — leaks a listener per screen visit.
- Task worker that is not idempotent — Cloud Tasks retries; check `status === "done"` first and write results with `update` guarded by the status, or `create()` a results doc.

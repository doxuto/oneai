import { HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import type { Deps } from "../lib/deps.js";
import { rethrow } from "../lib/errors.js";
import { requireCaller, type Caller } from "../lib/handler.js";
import { log, logDone } from "../lib/logging.js";
import { periodIdFor } from "../lib/time.js";
import { parse } from "../lib/validate.js";
import { minuteRef, sourcePartPath, type MinuteDoc } from "../minutes/_shared.js";
import { MAX_SOURCE_BYTES, type MinuteStatus } from "../minutes/types.js";
import { glossaryTermsFor, mergeKeyterms } from "../glossary/handler.js";
import { consumeQuota, refundQuota } from "../quota/quota.js";
import { effectivePlan, type UserDoc } from "../users/_shared.js";
import {
  CancelTranscriptionInput,
  StartTranscriptionInput,
  TASK_QUEUE,
  type CancelTranscriptionOutput,
  type JobDoc,
  type StartTranscriptionOutput,
} from "./types.js";

/** Statuses from which a (re)start is allowed. */
const STARTABLE: ReadonlySet<string> = new Set(["uploading", "failed", "cancelled"]);
/** Statuses from which a cancel is allowed. */
const CANCELLABLE: ReadonlySet<string> = new Set(["queued", "transcribing", "summarizing"]);

export async function startTranscriptionHandler(
  caller: Caller | undefined,
  raw: unknown,
  deps: Deps,
): Promise<StartTranscriptionOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(StartTranscriptionInput, raw, deps.minClientVersion);
  const now = deps.now();
  const jobRef = deps.db.doc(`transcriptionJobs/${input.requestId}`);

  try {
    // 1. Verify the upload actually landed before spending anything.
    const mRef = minuteRef(deps.db, uid, input.minuteId);
    const pre = await mRef.get();
    if (!pre.exists) throw new HttpsError("not-found", "Note not found");
    const preDoc = (pre.data() ?? {}) as MinuteDoc;

    // Idempotency: same requestId ⇒ same answer, no second charge.
    const existing = await jobRef.get();
    if (existing.exists) {
      const j = existing.data() as JobDoc;
      if (j.uid !== uid || j.minuteId !== input.minuteId) {
        throw new HttpsError("invalid-argument", "requestId was used for a different note", { field: "requestId" });
      }
      log.info("transcribe.start.duplicate", { uid, minuteId: input.minuteId, jobId: input.requestId });
      return { minuteId: input.minuteId, status: (preDoc.status as MinuteStatus) ?? "queued", duplicate: true };
    }

    if (!STARTABLE.has(preDoc.status ?? "")) {
      throw new HttpsError("failed-precondition", "This note is already being processed", {
        reason: "alreadyProcessing", status: preDoc.status ?? null,
      });
    }
    if (!preDoc.sourcePath) throw new HttpsError("failed-precondition", "Nothing has been uploaded yet", { reason: "noSource" });

    if (input.partCount) {
      // Chunked recording: every part must be there; the worker joins them.
      const ext = preDoc.sourcePath.split(".").pop() ?? "m4a";
      let total = 0;
      for (let i = 0; i < input.partCount; i++) {
        const part = deps.bucket.file(sourcePartPath(uid, input.minuteId, i, ext));
        const [exists] = await part.exists();
        if (!exists) throw new HttpsError("failed-precondition", "Upload has not finished", { reason: "noSource", missingPart: i });
        total += Number((await part.getMetadata())[0].size ?? 0);
      }
      if (total > MAX_SOURCE_BYTES) throw new HttpsError("failed-precondition", "Recording is too large", { reason: "tooLarge", maxSizeBytes: MAX_SOURCE_BYTES });
      if (preDoc.sourceSizeBytes && total !== preDoc.sourceSizeBytes) {
        throw new HttpsError("failed-precondition", "Uploaded file size does not match", { reason: "sizeMismatch" });
      }
    } else {
      const file = deps.bucket.file(preDoc.sourcePath);
      const [exists] = await file.exists();
      if (!exists) throw new HttpsError("failed-precondition", "Upload has not finished", { reason: "noSource" });
      const [meta] = await file.getMetadata();
      const size = Number(meta.size ?? 0);
      if (preDoc.sourceSizeBytes && size !== preDoc.sourceSizeBytes) {
        throw new HttpsError("failed-precondition", "Uploaded file size does not match", { reason: "sizeMismatch" });
      }
    }

    // 2. Plan + pre-check the client's declared duration against the cap.
    const userSnap = await deps.db.doc(`users/${uid}`).get();
    const plan = effectivePlan((userSnap.data() ?? {}) as UserDoc, now);
    const limits = deps.limits[plan];
    if (input.durationSeconds !== undefined && input.durationSeconds > limits.maxDurationSeconds) {
      throw new HttpsError("failed-precondition", "Recording is longer than your plan allows", {
        reason: "durationLimit", limitSeconds: limits.maxDurationSeconds,
      });
    }
    // S11-10: the user's glossary rides along with the one-off keywords.
    const keyterms = mergeKeyterms(input.keywords, await glossaryTermsFor(deps.db, uid));

    // Reserve the declared length (never less than a minute — the client's
    // number is a guess); the worker settles to the measured length. A PDF is
    // a flat charge.
    const chargedSeconds = preDoc.sourceType === "pdf"
      ? limits.pdfChargeSeconds
      : Math.max(60, Math.round(input.durationSeconds ?? 60));

    // 3. Charge + mark + create the job, atomically.
    const periodId = periodIdFor(now);
    await deps.db.runTransaction(async (tx) => {
      const cur = await tx.get(mRef);
      if (!STARTABLE.has(((cur.data() ?? {}) as MinuteDoc).status ?? "")) {
        throw new HttpsError("failed-precondition", "This note is already being processed", { reason: "alreadyProcessing" });
      }
      // Concurrency cap before the charge, so a refused start costs nothing.
      const active = await tx.get(
        deps.db.collection("transcriptionJobs").where("uid", "==", uid).where("state", "in", ["queued", "running"]).limit(limits.maxActiveJobs),
      );
      if (active.size >= limits.maxActiveJobs) {
        throw new HttpsError("resource-exhausted", "Please wait for your current recording to finish", {
          reason: "tooManyActiveJobs", limit: limits.maxActiveJobs,
        });
      }
      await consumeQuota(tx, deps.db, uid, plan, limits, now, chargedSeconds);
      const job: JobDoc = {
        uid, minuteId: input.minuteId, requestId: input.requestId, state: "queued", attempt: 0, periodId,
        chargedSeconds,
        quotaRefunded: false,
        options: {
          audioLanguage: input.audioLanguage, summaryLanguage: input.summaryLanguage, keywords: input.keywords,
          keyterms,
          description: input.description ?? null, template: input.template, timezone: input.timezone,
        },
        createdAt: FieldValue.serverTimestamp() as unknown as FirebaseFirestore.Timestamp,
        error: null,
      };
      tx.create(jobRef, job);
      tx.update(mRef, {
        status: "queued",
        statusUpdatedAt: FieldValue.serverTimestamp(),
        failure: null,
        summaryLanguage: input.summaryLanguage,
        keywords: input.keywords,
        description: input.description ?? null,
        template: input.template,
        timezone: input.timezone,
        sourceParts: input.partCount ?? null,
        updatedAt: FieldValue.serverTimestamp(),
      });
    });

    // 4. Hand off. If the queue is down, undo the charge — do not leave a
    //    'queued' note nobody will ever process.
    try {
      await deps.services.enqueue(TASK_QUEUE, { uid, minuteId: input.minuteId, jobId: input.requestId });
    } catch (err) {
      log.error("transcribe.enqueue_failed", { uid, minuteId: input.minuteId, error: String(err) });
      await deps.db.runTransaction(async (tx) => {
        await refundQuota(tx, deps.db, uid, periodId, chargedSeconds);
        tx.update(jobRef, { state: "failed", quotaRefunded: true, error: { code: "enqueue_failed", message: "Could not queue the job" }, finishedAt: FieldValue.serverTimestamp() });
        tx.update(mRef, { status: "failed", failure: { code: "enqueue_failed", message: "Could not start processing. Please try again." }, statusUpdatedAt: FieldValue.serverTimestamp() });
      });
      throw new HttpsError("unavailable", "Could not start processing. Please try again.");
    }

    logDone("transcribe.started", startedAt, { uid, minuteId: input.minuteId, plan, jobId: input.requestId });
    return { minuteId: input.minuteId, status: "queued", duplicate: false };
  } catch (err) {
    return rethrow(err, "transcribe.start.failed", { uid, minuteId: input.minuteId });
  }
}

export async function cancelTranscriptionHandler(
  caller: Caller | undefined,
  raw: unknown,
  deps: Deps,
): Promise<CancelTranscriptionOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(CancelTranscriptionInput, raw, deps.minClientVersion);

  try {
    const mRef = minuteRef(deps.db, uid, input.minuteId);
    await deps.db.runTransaction(async (tx) => {
      const snap = await tx.get(mRef);
      if (!snap.exists) throw new HttpsError("not-found", "Note not found");
      const doc = (snap.data() ?? {}) as MinuteDoc;
      if (!CANCELLABLE.has(doc.status ?? "")) {
        throw new HttpsError("failed-precondition", "Nothing to cancel", { reason: "notProcessing", status: doc.status ?? null });
      }
      // Find the live job for this note (at most one is not finished).
      const jobs = await tx.get(
        deps.db.collection("transcriptionJobs").where("uid", "==", uid).where("minuteId", "==", input.minuteId)
          .where("state", "in", ["queued", "running"]).limit(1),
      );
      const job = jobs.docs[0];
      if (job) {
        const j = job.data() as JobDoc;
        if (!j.quotaRefunded) await refundQuota(tx, deps.db, uid, j.periodId, j.chargedSeconds ?? 0);
        tx.update(job.ref, { state: "cancelled", quotaRefunded: true, finishedAt: FieldValue.serverTimestamp() });
      }
      tx.update(mRef, { status: "cancelled", statusUpdatedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
    });
    logDone("transcribe.cancelled", startedAt, { uid, minuteId: input.minuteId });
    return {};
  } catch (err) {
    return rethrow(err, "transcribe.cancel.failed", { uid, minuteId: input.minuteId });
  }
}

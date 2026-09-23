/**
 * The worker's job, as a plain function so it is tested against the
 * emulator with fake STT/LLM. State machine on the minute:
 *
 *   queued → transcribing → summarizing → ready
 *                 ↘ failed (permanent error, or retries exhausted) — quota refunded
 *   cancelled at any check-point ⇒ stop quietly, no writes
 */
import { HttpsError } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { summarizeTranscript } from "../ai/summarize.js";
import type { Deps } from "../lib/deps.js";
import { log } from "../lib/logging.js";
import { previewOf } from "../lib/stt/convert.js";
import { sttLanguageCode } from "../lib/stt/languages.js";
import { minuteRef, transcriptPath, type MinuteDoc } from "../minutes/_shared.js";
import type { Transcript } from "../minutes/types.js";
import { refundQuota } from "../quota/quota.js";
import { effectivePlan, type UserDoc } from "../users/_shared.js";
import type { JobDoc, TaskPayload } from "./types.js";

export interface RunOptions {
  /** 0-based attempt index from Cloud Tasks. */
  attempt: number;
  maxAttempts: number;
}

export type RunOutcome = "done" | "skipped" | "failed" | "retry";

const RETRYABLE: ReadonlySet<string> = new Set(["unavailable", "deadline-exceeded", "resource-exhausted", "aborted", "internal"]);

class Cancelled extends Error {}

export async function runPipeline(payload: TaskPayload, deps: Deps, opts: RunOptions): Promise<RunOutcome> {
  const { uid, minuteId, jobId } = payload;
  const jobRef = deps.db.doc(`transcriptionJobs/${jobId}`);
  const mRef = minuteRef(deps.db, uid, minuteId);
  const t0 = Date.now();

  // ---- claim ------------------------------------------------------------
  const jobSnap = await jobRef.get();
  if (!jobSnap.exists) { log.warn("pipeline.no_job", { uid, minuteId, jobId }); return "skipped"; }
  const job = jobSnap.data() as JobDoc;
  if (job.state === "done" || job.state === "failed" || job.state === "cancelled") {
    log.info("pipeline.already_finished", { uid, minuteId, jobId, state: job.state });
    return "skipped";
  }
  await jobRef.update({ state: "running", attempt: opts.attempt + 1, startedAt: FieldValue.serverTimestamp() });

  const assertNotCancelled = async (): Promise<MinuteDoc> => {
    const snap = await mRef.get();
    const d = (snap.data() ?? {}) as MinuteDoc;
    if (!snap.exists || d.status === "cancelled") throw new Cancelled();
    return d;
  };

  try {
    const minute = await assertNotCancelled();
    if (!minute.sourcePath) throw new HttpsError("failed-precondition", "No source file", { reason: "noSource" });

    const userSnap = await deps.db.doc(`users/${uid}`).get();
    const plan = effectivePlan((userSnap.data() ?? {}) as UserDoc, deps.now());
    const limits = deps.limits[plan];

    // ---- transcribing ---------------------------------------------------
    await mRef.update({ status: "transcribing", statusUpdatedAt: FieldValue.serverTimestamp() });
    const [bytes] = await deps.bucket.file(minute.sourcePath).download();
    const contentType = minute.sourceContentType ?? "application/octet-stream";

    let transcript: Transcript;
    let durationSeconds: number | null = null;
    let stt: { vendor: string; model: string } | null = null;

    if (minute.sourceType === "pdf") {
      const text = await deps.services.pdfText(bytes);
      transcript = { durationSeconds: 0, languageCode: null, languageProbability: null, text,
        segments: [{ startSeconds: 0, endSeconds: 0, text, speakerId: "document", speakerLabel: "Document" }] };
    } else {
      durationSeconds = await deps.services.audioDurationSeconds(bytes, contentType);
      if (durationSeconds !== null && durationSeconds > limits.maxDurationSeconds) {
        throw new HttpsError("failed-precondition", "Recording is longer than your plan allows", {
          reason: "durationLimit", limitSeconds: limits.maxDurationSeconds, actualSeconds: Math.round(durationSeconds),
        });
      }
      const result = await deps.services.stt.transcribe({
        audio: bytes, contentType, fileName: minute.sourcePath.split("/").pop() ?? "audio",
        languageCode: sttLanguageCode(job.options.audioLanguage),
      });
      transcript = result.transcript;
      stt = { vendor: result.vendor, model: result.model };
      // Measured from the transcript when the container told us nothing.
      durationSeconds ??= transcript.durationSeconds || null;
      if (durationSeconds !== null && durationSeconds > limits.maxDurationSeconds) {
        throw new HttpsError("failed-precondition", "Recording is longer than your plan allows", {
          reason: "durationLimit", limitSeconds: limits.maxDurationSeconds, actualSeconds: Math.round(durationSeconds),
        });
      }
    }

    if (transcript.text.trim().length === 0) {
      throw new HttpsError("failed-precondition", "No speech was detected", { reason: "noSpeech" });
    }

    await assertNotCancelled();
    const tPath = transcriptPath(uid, minuteId);
    await deps.bucket.file(tPath).save(JSON.stringify(transcript), { contentType: "application/json", resumable: false });

    // ---- summarizing ----------------------------------------------------
    await mRef.update({
      status: "summarizing", statusUpdatedAt: FieldValue.serverTimestamp(),
      transcriptPath: tPath, transcriptPreview: previewOf(transcript.text),
      durationSeconds, languageCode: transcript.languageCode, languageProbability: transcript.languageProbability,
      stt, // which vendor/model produced this transcript — lets us compare vendors later
    });

    const s = await summarizeTranscript(deps.services.llmHeavy, {
      transcript: transcript.text, summaryLanguage: job.options.summaryLanguage,
      description: job.options.description, now: deps.now(), timezone: job.options.timezone,
    });

    await assertNotCancelled();

    // ---- ready ----------------------------------------------------------
    const batch = deps.db.batch();
    batch.update(mRef, {
      status: "ready", statusUpdatedAt: FieldValue.serverTimestamp(), failure: null,
      title: s.title, iconEmoji: s.iconEmoji, contentKind: s.contentKind, summary: s.summary,
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (s.calendarEvents.length > 0) {
      batch.set(mRef.collection("artifacts").doc("calendarEvents"), {
        kind: "calendarEvents", data: { events: s.calendarEvents }, model: s.model, generatedAt: FieldValue.serverTimestamp(),
      });
    }
    batch.update(jobRef, { state: "done", finishedAt: FieldValue.serverTimestamp(), error: null });
    await batch.commit();

    log.info("pipeline.done", { uid, minuteId, jobId, ms: Date.now() - t0, plan, sourceType: minute.sourceType ?? null,
      durationSeconds, stt: stt ? `${stt.vendor}/${stt.model}` : null, model: s.model, tokensIn: s.tokens.input, tokensOut: s.tokens.output });
    return "done";
  } catch (err) {
    if (err instanceof Cancelled) {
      await jobRef.update({ state: "cancelled", finishedAt: FieldValue.serverTimestamp() });
      log.info("pipeline.cancelled", { uid, minuteId, jobId });
      return "skipped";
    }
    const code = err instanceof HttpsError ? err.code : "internal";
    const retryable = RETRYABLE.has(code) && opts.attempt + 1 < opts.maxAttempts;
    log.warn("pipeline.error", { uid, minuteId, jobId, code, attempt: opts.attempt + 1, retryable, error: String(err) });

    if (retryable) {
      await jobRef.update({ error: { code, message: String(err).slice(0, 300) } });
      throw err; // Cloud Tasks retries with backoff
    }

    // Permanent (or out of attempts): fail the note and give the credit back.
    const failure = { code, message: userMessage(err) };
    await deps.db.runTransaction(async (tx) => {
      const j = (await tx.get(jobRef)).data() as JobDoc | undefined;
      if (j && !j.quotaRefunded) await refundQuota(tx, deps.db, uid, j.periodId);
      tx.update(jobRef, { state: "failed", quotaRefunded: true, finishedAt: FieldValue.serverTimestamp(), error: failure });
      tx.update(mRef, { status: "failed", failure, statusUpdatedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
    });
    return "failed";
  }
}

/** What the note shows the user. Never provider text. */
function userMessage(err: unknown): string {
  if (err instanceof HttpsError) {
    const reason = (err.details as { reason?: string } | undefined)?.reason;
    switch (reason) {
      case "durationLimit": return "This recording is longer than your plan allows.";
      case "noSpeech": return "No speech was detected in this recording.";
      case "pdfNoText": return "This PDF has no extractable text.";
      case "pdfUnreadable": return "This PDF could not be read.";
      case "safety": return "The content could not be processed.";
      case "noSource": return "The uploaded file is missing.";
      default: break;
    }
    if (err.code === "deadline-exceeded") return "Processing took too long. Please try again.";
    if (err.code === "resource-exhausted") return "The service is busy. Please try again shortly.";
  }
  return "Something went wrong while processing. Please try again.";
}

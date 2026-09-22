import { createHash } from "node:crypto";
import { HttpsError } from "firebase-functions/v2/https";
import { FieldValue, type DocumentReference } from "firebase-admin/firestore";
import type { ZodType, ZodTypeDef } from "zod";
import type { Deps } from "../lib/deps.js";
import type { LlmClient } from "../lib/llm/types.js";
import { log } from "../lib/logging.js";
import { toTranscript } from "../minutes/_shared.js";
import { loadOwnedMinute } from "../minutes/_shared.js";
import type { Transcript } from "../minutes/types.js";
import { trimTranscript } from "./summarize.js";

export type ArtifactKind = "shortQuestions" | "quiz" | "flashcards" | "mindmap" | "speakers" | "calendarEvents";

export interface LoadedTranscript {
  minuteRef: DocumentReference;
  transcript: Transcript;
  /** sha256 of the transcript text; artifacts remember which text they came from. */
  sourceHash: string;
}

/** A note must be `ready` with a transcript before any AI feature runs. */
export async function loadReadyTranscript(deps: Deps, uid: string, minuteId: string): Promise<LoadedTranscript> {
  const { ref, doc } = await loadOwnedMinute(deps.db, uid, minuteId);
  if (doc.status !== "ready" || !doc.transcriptPath) {
    throw new HttpsError("failed-precondition", "This note is not ready yet", { reason: "notReady", status: doc.status ?? null });
  }
  let transcript: Transcript | null;
  try {
    const [buf] = await deps.bucket.file(doc.transcriptPath).download();
    transcript = toTranscript(JSON.parse(buf.toString("utf8")));
  } catch (err) {
    log.error("artifact.transcript_unreadable", { uid, minuteId, error: String(err) });
    throw new HttpsError("unavailable", "The transcript could not be read");
  }
  if (!transcript || transcript.text.trim().length === 0) {
    throw new HttpsError("failed-precondition", "This note has no transcript text", { reason: "noSpeech" });
  }
  return { minuteRef: ref, transcript, sourceHash: createHash("sha256").update(transcript.text).digest("hex") };
}

export function artifactRef(minuteRef: DocumentReference, kind: ArtifactKind): DocumentReference {
  return minuteRef.collection("artifacts").doc(kind);
}

/**
 * Cache-or-generate. A cached artifact is used only when its sourceHash
 * matches the current transcript, so a re-transcription invalidates it.
 * A failed generation is NEVER written — v1 cached `{mindmap:{title:"Untitled",children:[]}}`
 * on error and then served that forever.
 */
export async function generateArtifact<T>(opts: {
  deps: Deps;
  llm: LlmClient;
  uid: string;
  loaded: LoadedTranscript;
  kind: ArtifactKind;
  schema: ZodType<T, ZodTypeDef, unknown>;
  prompt: string;
  system?: string;
  maxOutputTokens: number;
  force?: boolean;
}): Promise<{ data: T; cached: boolean }> {
  const ref = artifactRef(opts.loaded.minuteRef, opts.kind);
  if (!opts.force) {
    const snap = await ref.get();
    const d = snap.data() as { sourceHash?: string; data?: unknown } | undefined;
    if (d && d.sourceHash === opts.loaded.sourceHash) {
      const parsed = opts.schema.safeParse(d.data);
      if (parsed.success) return { data: parsed.data, cached: true };
      log.warn("artifact.cache_invalid", { uid: opts.uid, kind: opts.kind });
    }
  }
  const { data, model, tokens } = await opts.llm.generateJson<T>({
    name: opts.kind, system: opts.system, prompt: opts.prompt, schema: opts.schema, maxOutputTokens: opts.maxOutputTokens,
  });
  await ref.set({ kind: opts.kind, data, model, sourceHash: opts.loaded.sourceHash, generatedAt: FieldValue.serverTimestamp() });
  log.info("artifact.generated", { uid: opts.uid, kind: opts.kind, model, tokensIn: tokens.input, tokensOut: tokens.output });
  return { data, cached: false };
}

export const promptTranscript = (t: Transcript) => trimTranscript(t.text);

/** "speaker_0: Hello everyone.\nspeaker_1: Sure." — what the speaker-mapping prompt needs. */
export function transcriptBySpeaker(t: Transcript): string {
  return trimTranscript(t.segments.map((s) => `${s.speakerId}: ${s.text}`).join("\n"));
}

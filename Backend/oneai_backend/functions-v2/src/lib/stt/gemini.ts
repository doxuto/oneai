/**
 * Gemini as a speech-to-text vendor. The model listens to the audio and
 * answers with a JSON transcript (diarised, timestamped) constrained by a
 * response schema. Timestamps are the model's estimate — good for "jump to"
 * but not sample-accurate like Scribe's.
 *
 * Small files go inline (base64); above INLINE_MAX_BYTES they are uploaded
 * through the Files API first and referenced by URI.
 */
import { HttpsError } from "firebase-functions/v2/https";
import { z } from "zod";
import { mapProviderError } from "../errors.js";
import { log } from "../logging.js";
import { speakerIdOf, speakerLabelOf } from "./convert.js";
import type { SttClient, SttRequest, SttResult, Transcript } from "./types.js";

export interface GeminiSttOptions {
  apiKey: string;
  model: string;
  timeoutMs: number;
  fetchImpl?: typeof fetch;
  /** Override for tests. */
  baseUrl?: string;
  /** Files above this size go through the Files API. */
  inlineMaxBytes?: number;
  /** How long to wait between Files API state polls. */
  pollIntervalMs?: number;
}

/** Gemini's request limit is 20 MB for the whole request; keep headroom for base64 + prompt. */
export const INLINE_MAX_BYTES = 14 * 1024 * 1024;

const Segment = z.object({
  start: z.number().min(0),
  end: z.number().min(0),
  speaker: z.string().min(1).max(32),
  text: z.string(),
});
export const GeminiTranscript = z.object({
  language_code: z.string().min(2).max(8),
  segments: z.array(Segment).max(5000),
});
export type GeminiTranscript = z.infer<typeof GeminiTranscript>;

const RESPONSE_SCHEMA = {
  type: "object",
  properties: {
    language_code: { type: "string", description: "ISO-639-3 code of the spoken language, e.g. eng, vie" },
    segments: {
      type: "array",
      items: {
        type: "object",
        properties: {
          start: { type: "number", description: "start time in seconds" },
          end: { type: "number", description: "end time in seconds" },
          speaker: { type: "string", description: "speaker_0, speaker_1, … in order of first appearance" },
          text: { type: "string", description: "verbatim words spoken in this turn" },
        },
        required: ["start", "end", "speaker", "text"],
      },
    },
  },
  required: ["language_code", "segments"],
};

export function sttPrompt(languageCode: string | undefined, keyterms: string[] = []): string {
  const lang = languageCode ? `The audio is in the language with ISO-639-3 code '${languageCode}'.` : "Detect the spoken language.";
  const terms = keyterms.length ? `These names and terms may occur; spell them exactly like this: ${keyterms.map((t) => `"${t}"`).join(", ")}.` : "";
  return [
    "Transcribe this audio verbatim.",
    lang,
    "Split it into speaker turns: a new segment whenever the speaker changes. Label speakers speaker_0, speaker_1, … in order of first appearance and keep the same label for the same voice.",
    "Give start and end in seconds for every segment. Do not summarise, translate, or omit filler words; keep numbers and names as spoken.",
    "If there is no speech at all, return an empty segments list.",
    terms,
  ].filter(Boolean).join(" ");
}

/** Gemini wants canonical audio MIME types; containers report a few aliases. */
export function geminiMime(contentType: string): string {
  const ct = contentType.toLowerCase().split(";")[0]!.trim();
  switch (ct) {
    case "audio/mpeg": case "audio/mp3": case "audio/mpeg3": return "audio/mp3";
    case "audio/x-m4a": case "audio/m4a": case "audio/mp4": case "audio/aac": case "audio/x-aac": return "audio/aac";
    case "audio/wav": case "audio/x-wav": case "audio/wave": return "audio/wav";
    case "audio/ogg": case "audio/opus": return "audio/ogg";
    case "audio/flac": case "audio/x-flac": return "audio/flac";
    case "audio/aiff": case "audio/x-aiff": return "audio/aiff";
    case "audio/webm": return "audio/webm";
    default: return ct.startsWith("audio/") ? ct : "audio/mp3";
  }
}

interface GeminiReply {
  candidates?: { content?: { parts?: { text?: string }[] }; finishReason?: string }[];
  promptFeedback?: { blockReason?: string };
  usageMetadata?: { promptTokenCount?: number; candidatesTokenCount?: number };
}

export function toTranscript(g: GeminiTranscript): Transcript {
  const segments = g.segments
    .filter((s) => s.text.trim().length > 0)
    .map((s) => ({
      startSeconds: round3(s.start),
      endSeconds: round3(Math.max(s.end, s.start)),
      text: s.text.trim(),
      speakerId: speakerIdOf(s.speaker),
      speakerLabel: speakerLabelOf(speakerIdOf(s.speaker)),
    }));
  const durationSeconds = segments.reduce((m, s) => Math.max(m, s.endSeconds), 0);
  return {
    durationSeconds,
    languageCode: g.language_code.toLowerCase(),
    languageProbability: null, // Gemini does not report one
    text: segments.map((s) => s.text).join(" "),
    segments,
  };
}

const round3 = (n: number) => Math.round(n * 1000) / 1000;

export function geminiSttClient(opts: GeminiSttOptions): SttClient {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const base = (opts.baseUrl ?? "https://generativelanguage.googleapis.com").replace(/\/$/, "");
  const inlineMax = opts.inlineMaxBytes ?? INLINE_MAX_BYTES;
  const pollMs = opts.pollIntervalMs ?? 2000;
  const key = `key=${encodeURIComponent(opts.apiKey)}`;

  async function call(path: string, init: RequestInit, signal: AbortSignal): Promise<Response> {
    try {
      return await fetchImpl(`${base}${path}${path.includes("?") ? "&" : "?"}${key}`, { ...init, signal });
    } catch (err) {
      if (signal.aborted) throw new HttpsError("deadline-exceeded", "Transcription took too long");
      throw mapProviderError("gemini-stt", undefined, err);
    }
  }
  async function ensureOk(res: Response, what: string): Promise<void> {
    if (res.ok) return;
    const text = (await res.text().catch(() => "")).slice(0, 300);
    throw mapProviderError("gemini-stt", res.status, new Error(text), { step: what });
  }

  /** Files API: raw upload, then poll until the file is ACTIVE. Returns the URI. */
  async function upload(req: SttRequest, mime: string, signal: AbortSignal): Promise<{ uri: string; name: string }> {
    const res = await call("/upload/v1beta/files", {
      method: "POST",
      headers: {
        "X-Goog-Upload-Protocol": "raw",
        "X-Goog-Upload-Header-Content-Type": mime,
        "X-Goog-File-Name": req.fileName,
        "content-type": mime,
      },
      body: req.audio,
    }, signal);
    await ensureOk(res, "upload");
    const json = (await res.json()) as { file?: { uri?: string; name?: string; state?: string } };
    const name = json.file?.name;
    let uri = json.file?.uri;
    let state = json.file?.state;
    if (!uri || !name) throw new HttpsError("unavailable", "Upload returned no file");
    // Audio is usually ACTIVE at once; large files can sit in PROCESSING briefly.
    for (let i = 0; state === "PROCESSING" && i < 60; i++) {
      await new Promise((r) => setTimeout(r, pollMs));
      if (signal.aborted) throw new HttpsError("deadline-exceeded", "Transcription took too long");
      const poll = await call(`/v1beta/${name}`, { method: "GET" }, signal);
      await ensureOk(poll, "poll");
      const f = (await poll.json()) as { state?: string; uri?: string };
      state = f.state;
      uri = f.uri ?? uri;
    }
    if (state === "FAILED") throw new HttpsError("internal", "Gemini could not process the upload");
    return { uri, name };
  }

  return {
    vendor: "gemini",
    model: opts.model,
    async transcribe(req: SttRequest, outerSignal?: AbortSignal): Promise<SttResult> {
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(new Error("stt timeout")), opts.timeoutMs);
      outerSignal?.addEventListener("abort", () => ctrl.abort(outerSignal.reason));
      const startedAt = Date.now();
      const mime = geminiMime(req.contentType);
      let uploadedName: string | undefined;

      try {
        let audioPart: Record<string, unknown>;
        if (req.audio.byteLength <= inlineMax) {
          audioPart = { inline_data: { mime_type: mime, data: Buffer.from(req.audio).toString("base64") } };
        } else {
          const up = await upload(req, mime, ctrl.signal);
          uploadedName = up.name;
          audioPart = { file_data: { mime_type: mime, file_uri: up.uri } };
        }

        const body = {
          contents: [{ role: "user", parts: [{ text: sttPrompt(req.languageCode, req.keyterms) }, audioPart] }],
          generationConfig: { temperature: 0, maxOutputTokens: 32768, responseMimeType: "application/json", responseSchema: RESPONSE_SCHEMA },
        };
        const res = await call(`/v1beta/models/${opts.model}:generateContent`, {
          method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body),
        }, ctrl.signal);
        await ensureOk(res, "generate");
        const json = (await res.json()) as GeminiReply;

        if (json.promptFeedback?.blockReason || json.candidates?.[0]?.finishReason === "SAFETY") {
          throw new HttpsError("failed-precondition", "The content could not be processed", { reason: "safety" });
        }
        const text = json.candidates?.[0]?.content?.parts?.map((p) => p.text ?? "").join("") ?? "";
        if (!text) throw new HttpsError("unavailable", "Empty model response");
        let parsed: unknown;
        try { parsed = JSON.parse(text); } catch {
          log.warn("gemini-stt.bad_json", { head: text.slice(0, 120) });
          throw new HttpsError("unavailable", "Model returned malformed output");
        }
        const checked = GeminiTranscript.safeParse(parsed);
        if (!checked.success) {
          log.warn("gemini-stt.schema_mismatch", { issues: checked.error.issues.length });
          throw new HttpsError("unavailable", "Model output did not match the expected shape");
        }
        const transcript = toTranscript(checked.data);
        log.info("gemini-stt.done", {
          model: opts.model, ms: Date.now() - startedAt, segments: transcript.segments.length, language: transcript.languageCode,
          inline: uploadedName === undefined, tokensIn: json.usageMetadata?.promptTokenCount ?? 0, tokensOut: json.usageMetadata?.candidatesTokenCount ?? 0,
        });
        return { transcript, vendor: "gemini", model: opts.model };
      } finally {
        clearTimeout(timer);
        if (uploadedName) {
          // Best effort; files expire on their own after 48 h anyway.
          fetchImpl(`${base}/v1beta/${uploadedName}?${key}`, { method: "DELETE" }).catch(() => undefined);
        }
      }
    },
  };
}

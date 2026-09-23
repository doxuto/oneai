import type { Transcript } from "../../minutes/types.js";

/** Vendors the factory knows. Adding one = one adapter file + one case in index.ts. */
export type SttVendor = "elevenlabs" | "gemini";

export interface SttRequest {
  /** Audio bytes. */
  audio: Uint8Array;
  contentType: string;
  fileName: string;
  /** ISO-639-3 or undefined for auto-detect. */
  languageCode: string | undefined;
  /** Names / jargon to spell exactly (user keywords + glossary). Adapters that cannot use it ignore it. */
  keyterms?: string[];
}

/** Every adapter returns the SAME shape; nothing downstream knows the vendor. */
export interface SttResult {
  transcript: Transcript;
  /** Which adapter actually produced it (after any fallback) — stored on the note. */
  vendor: string;
  model: string;
}

export interface SttClient {
  readonly vendor: string;
  readonly model: string;
  transcribe(req: SttRequest, signal?: AbortSignal): Promise<SttResult>;
}

export type { Transcript };

// ---- ElevenLabs Scribe raw response (used by its adapter + convert.ts) ----

export interface ElevenLabsWord {
  type?: "word" | "spacing" | "audio_event";
  text?: string;
  start?: number | string;
  end?: number | string;
  speaker_id?: string | number;
}

export interface ElevenLabsResponse {
  text?: string;
  language_code?: string;
  language_probability?: number;
  words?: ElevenLabsWord[];
}

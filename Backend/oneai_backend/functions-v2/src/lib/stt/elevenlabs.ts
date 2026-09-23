import { HttpsError } from "firebase-functions/v2/https";
import { mapProviderError } from "../errors.js";
import { log } from "../logging.js";
import { convertScribe } from "./convert.js";
import type { ElevenLabsResponse, SttClient, SttRequest, SttResult } from "./types.js";

export interface ElevenLabsOptions {
  apiKey: string;
  model: string;
  /** Must be comfortably below the worker's timeoutSeconds. */
  timeoutMs: number;
  fetchImpl?: typeof fetch;
  endpoint?: string;
}

/**
 * ElevenLabs Scribe over native fetch. v1 used axios with a 300–600 s timeout
 * inside a 240 s function; here the deadline is explicit and shorter than the
 * worker budget so we fail with a mappable error instead of a platform kill.
 */
export function elevenLabsClient(opts: ElevenLabsOptions): SttClient {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const endpoint = opts.endpoint ?? "https://api.elevenlabs.io/v1/speech-to-text";

  return {
    vendor: "elevenlabs",
    model: opts.model,
    async transcribe(req: SttRequest, outerSignal?: AbortSignal): Promise<SttResult> {
      const form = new FormData();
      form.append("model_id", opts.model);
      form.append("diarize", "true");
      form.append("tag_audio_events", "true");
      if (req.languageCode) form.append("language_code", req.languageCode);
      form.append("file", new Blob([req.audio], { type: req.contentType }), req.fileName);

      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(new Error("stt timeout")), opts.timeoutMs);
      outerSignal?.addEventListener("abort", () => ctrl.abort(outerSignal.reason));
      const startedAt = Date.now();

      let res: Response;
      try {
        res = await fetchImpl(endpoint, {
          method: "POST",
          headers: { "xi-api-key": opts.apiKey },
          body: form,
          signal: ctrl.signal,
        });
      } catch (err) {
        clearTimeout(timer);
        if (ctrl.signal.aborted) {
          throw new HttpsError("deadline-exceeded", "Transcription took too long");
        }
        throw mapProviderError("elevenlabs", undefined, err);
      }
      clearTimeout(timer);

      if (!res.ok) {
        // Never log the body verbatim in full — it can echo our request.
        const body = (await res.text().catch(() => "")).slice(0, 300);
        log.warn("elevenlabs.non_ok", { status: res.status, ms: Date.now() - startedAt, body });
        throw mapProviderError("elevenlabs", res.status, new Error(body));
      }

      const json = (await res.json()) as ElevenLabsResponse;
      log.info("elevenlabs.done", {
        ms: Date.now() - startedAt,
        words: Array.isArray(json.words) ? json.words.length : 0,
        language: json.language_code ?? null,
      });
      return { transcript: convertScribe(json), vendor: "elevenlabs", model: opts.model };
    },
  };
}

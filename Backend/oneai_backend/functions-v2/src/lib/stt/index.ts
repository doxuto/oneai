/**
 * STT factory + fallback. The pipeline sees one `SttClient`; which vendor
 * answers is configuration (STT_VENDOR / STT_FALLBACK_VENDOR), not code.
 */
import { HttpsError } from "firebase-functions/v2/https";
import { log } from "../logging.js";
import type { SttClient, SttRequest, SttResult, SttVendor } from "./types.js";

export interface SttVendorConfig {
  elevenlabs: { apiKey: string; model: string };
  gemini: { apiKey: string; model: string };
  timeoutMs: number;
  fetchImpl?: typeof fetch;
}

export function parseSttVendor(raw: string | undefined | null): SttVendor | null {
  const v = (raw ?? "").trim().toLowerCase();
  if (v === "elevenlabs" || v === "gemini") return v;
  return null;
}

export async function makeStt(vendor: SttVendor, cfg: SttVendorConfig): Promise<SttClient> {
  switch (vendor) {
    case "elevenlabs": {
      const { elevenLabsClient } = await import("./elevenlabs.js");
      return elevenLabsClient({ ...cfg.elevenlabs, timeoutMs: cfg.timeoutMs, fetchImpl: cfg.fetchImpl });
    }
    case "gemini": {
      const { geminiSttClient } = await import("./gemini.js");
      return geminiSttClient({ ...cfg.gemini, timeoutMs: cfg.timeoutMs, fetchImpl: cfg.fetchImpl });
    }
  }
}

/** Errors that say "the vendor is having a bad moment", not "this audio is bad". */
export const FALLBACK_ON: ReadonlySet<string> = new Set(["unavailable", "resource-exhausted", "internal"]);

/**
 * Try `primary`; if it fails with a vendor-side error, try `secondary` once.
 * A deadline is NOT retried (the worker budget is nearly spent), and neither
 * is anything that describes the input (safety, invalid-argument, …).
 */
export function withSttFallback(primary: SttClient, secondary: SttClient): SttClient {
  return {
    vendor: `${primary.vendor}+${secondary.vendor}`,
    model: primary.model,
    async transcribe(req: SttRequest, signal?: AbortSignal): Promise<SttResult> {
      try {
        return await primary.transcribe(req, signal);
      } catch (err) {
        const code = err instanceof HttpsError ? err.code : "internal";
        if (!FALLBACK_ON.has(code) || signal?.aborted) throw err;
        log.warn("stt.fallback", { from: primary.vendor, to: secondary.vendor, code });
        return secondary.transcribe(req, signal);
      }
    },
  };
}

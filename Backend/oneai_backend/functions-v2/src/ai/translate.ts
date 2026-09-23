import { onCall, type CallableRequest, type CallableResponse } from "firebase-functions/v2/https";
import { liveDeps } from "../lib/deps.js";
import { callerOf } from "../lib/handler.js";
import { GEMINI_API_KEY, OPENAI_API_KEY } from "../lib/params.js";
import { translateHandler } from "./translation.js";
import type { TranslateOutput } from "./translation.js";

/** Streaming chunk shape, same as chat: { delta: string }. */
export interface TranslateChunk { delta: string }

/**
 * S11-04. Streams the translation of a note's summary or transcript; the
 * full text is cached per (part, languageCode, transcript hash) so a second
 * open costs nothing and returns at once.
 */
export const translate = onCall(
  { enforceAppCheck: true, memory: "512MiB", timeoutSeconds: 300, maxInstances: 10, secrets: [OPENAI_API_KEY, GEMINI_API_KEY] },
  (request: CallableRequest<unknown>, response?: CallableResponse<TranslateChunk>): Promise<TranslateOutput> =>
    translateHandler(
      callerOf(request),
      request.data,
      liveDeps(),
      request.acceptsStreaming && response ? (delta) => { void response.sendChunk({ delta }); } : undefined,
    ),
);

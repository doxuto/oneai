import { onCall, type CallableRequest, type CallableResponse } from "firebase-functions/v2/https";
import { liveDeps } from "../lib/deps.js";
import { callerOf } from "../lib/handler.js";
import { GEMINI_API_KEY, OPENAI_API_KEY } from "../lib/params.js";
import { chatHandler } from "./handler.js";
import type { ChatOutput } from "./types.js";

/** Streaming chunk shape the Flutter client decodes: { delta: string }. */
export interface ChatChunk { delta: string }

/**
 * Streaming callable (firebase-functions ≥ 6.2). A client that does not accept
 * streaming gets the full answer in the result; one that does gets deltas as
 * they arrive and then the same result.
 */
export const chat = onCall(
  { enforceAppCheck: true, memory: "512MiB", timeoutSeconds: 120, maxInstances: 20, secrets: [OPENAI_API_KEY, GEMINI_API_KEY] },
  (request: CallableRequest<unknown>, response?: CallableResponse<ChatChunk>): Promise<ChatOutput> =>
    chatHandler(
      callerOf(request),
      request.data,
      liveDeps(),
      request.acceptsStreaming && response ? (delta) => { void response.sendChunk({ delta }); } : undefined,
    ),
);

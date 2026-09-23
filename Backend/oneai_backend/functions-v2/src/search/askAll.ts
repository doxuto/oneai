import { onCall, type CallableRequest, type CallableResponse } from "firebase-functions/v2/https";
import type { ChatChunk } from "../ai/chat.js";
import { liveDeps } from "../lib/deps.js";
import { callerOf } from "../lib/handler.js";
import { GEMINI_API_KEY, OPENAI_API_KEY } from "../lib/params.js";
import { askAllHandler } from "./handler.js";
import type { AskAllOutput } from "./types.js";

/** S11-01: one question over all of the caller's notes. Streams like `chat`; the result carries the cited sources. */
export const askAll = onCall(
  { enforceAppCheck: true, memory: "512MiB", timeoutSeconds: 120, maxInstances: 20, secrets: [OPENAI_API_KEY, GEMINI_API_KEY] },
  (request: CallableRequest<unknown>, response?: CallableResponse<ChatChunk>): Promise<AskAllOutput> =>
    askAllHandler(
      callerOf(request),
      request.data,
      liveDeps(),
      request.acceptsStreaming && response ? (delta) => { void response.sendChunk({ delta }); } : undefined,
    ),
);

import { onCall } from "firebase-functions/v2/https";
import { liveDeps } from "../lib/deps.js";
import { callerOf } from "../lib/handler.js";
import { GEMINI_API_KEY, OPENAI_API_KEY } from "../lib/params.js";
import { searchNotesHandler } from "./handler.js";

/** S11-02: semantic search over the caller's notes. Not charged as an AI call — one cheap embedding. */
export const searchNotes = onCall(
  { enforceAppCheck: true, memory: "256MiB", timeoutSeconds: 30, maxInstances: 20, secrets: [OPENAI_API_KEY, GEMINI_API_KEY] },
  (request) => searchNotesHandler(callerOf(request), request.data, liveDeps()),
);

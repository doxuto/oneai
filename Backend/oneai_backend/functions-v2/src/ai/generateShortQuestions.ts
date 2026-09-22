import { onCall, type CallableRequest } from "firebase-functions/v2/https";
import { liveDeps } from "../lib/deps.js";
import { callerOf } from "../lib/handler.js";
import { GEMINI_API_KEY, OPENAI_API_KEY } from "../lib/params.js";
import { generateShortQuestionsHandler } from "./handler.js";

export const generateShortQuestions = onCall(
  { enforceAppCheck: true, memory: "512MiB", timeoutSeconds: 120, maxInstances: 10, secrets: [OPENAI_API_KEY, GEMINI_API_KEY] },
  (request: CallableRequest<unknown>) => generateShortQuestionsHandler(callerOf(request), request.data, liveDeps()),
);

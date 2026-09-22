import { onCall, type CallableRequest } from "firebase-functions/v2/https";
import { liveDeps } from "../lib/deps.js";
import { callerOf } from "../lib/handler.js";
import { startTranscriptionHandler } from "./handler.js";

export const startTranscription = onCall(
  { enforceAppCheck: true, memory: "256MiB", timeoutSeconds: 30 },
  (request: CallableRequest<unknown>) => startTranscriptionHandler(callerOf(request), request.data, liveDeps()),
);

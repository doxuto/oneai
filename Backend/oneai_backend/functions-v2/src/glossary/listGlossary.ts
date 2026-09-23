import { onCall, type CallableRequest } from "firebase-functions/v2/https";
import { liveDeps } from "../lib/deps.js";
import { callerOf } from "../lib/handler.js";
import { listGlossaryHandler } from "./handler.js";

export const listGlossary = onCall(
  { enforceAppCheck: true, memory: "256MiB", timeoutSeconds: 30 },
  (request: CallableRequest<unknown>) => listGlossaryHandler(callerOf(request), request.data, liveDeps()),
);

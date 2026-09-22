import { onCall, type CallableRequest } from "firebase-functions/v2/https";
import { liveDeps } from "../lib/deps.js";
import { callerOf } from "../lib/handler.js";
import { deleteMinuteHandler } from "./handler.js";

export const deleteMinute = onCall(
  { enforceAppCheck: true, memory: "256MiB", timeoutSeconds: 30 },
  (request: CallableRequest<unknown>) => deleteMinuteHandler(callerOf(request), request.data, liveDeps()),
);

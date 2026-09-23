import { onCall, type CallableRequest } from "firebase-functions/v2/https";
import { liveDeps } from "../lib/deps.js";
import { callerOf } from "../lib/handler.js";
import { createShareLinkHandler } from "./handler.js";

export const createShareLink = onCall(
  { enforceAppCheck: true, memory: "256MiB", timeoutSeconds: 30, maxInstances: 10 },
  (request: CallableRequest<unknown>) => createShareLinkHandler(callerOf(request), request.data, liveDeps()),
);

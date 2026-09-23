import { onCall, type CallableRequest } from "firebase-functions/v2/https";
import { liveDeps } from "../lib/deps.js";
import { callerOf } from "../lib/handler.js";
import { revokeShareLinkHandler } from "./handler.js";

export const revokeShareLink = onCall(
  { enforceAppCheck: true, memory: "256MiB", timeoutSeconds: 30, maxInstances: 10 },
  (request: CallableRequest<unknown>) => revokeShareLinkHandler(callerOf(request), request.data, liveDeps()),
);

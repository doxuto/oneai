import { onCall, type CallableRequest } from "firebase-functions/v2/https";
import { liveDeps } from "../lib/deps.js";
import { callerOf } from "../lib/handler.js";
import { unregisterDeviceHandler } from "./handler.js";

export const unregisterDevice = onCall(
  { enforceAppCheck: true, memory: "256MiB", timeoutSeconds: 30, maxInstances: 10 },
  (request: CallableRequest<unknown>) => unregisterDeviceHandler(callerOf(request), request.data, liveDeps()),
);

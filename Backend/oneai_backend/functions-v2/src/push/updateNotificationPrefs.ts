import { onCall, type CallableRequest } from "firebase-functions/v2/https";
import { liveDeps } from "../lib/deps.js";
import { callerOf } from "../lib/handler.js";
import { updateNotificationPrefsHandler } from "./handler.js";

export const updateNotificationPrefs = onCall(
  { enforceAppCheck: true, memory: "256MiB", timeoutSeconds: 30, maxInstances: 10 },
  (request: CallableRequest<unknown>) => updateNotificationPrefsHandler(callerOf(request), request.data, liveDeps()),
);

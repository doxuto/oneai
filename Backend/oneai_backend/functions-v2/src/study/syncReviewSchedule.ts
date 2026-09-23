import { onCall, type CallableRequest } from "firebase-functions/v2/https";
import { liveDeps } from "../lib/deps.js";
import { callerOf } from "../lib/handler.js";
import { syncReviewScheduleHandler } from "./handler.js";

export const syncReviewSchedule = onCall(
  { enforceAppCheck: true, memory: "256MiB", timeoutSeconds: 30 },
  (request: CallableRequest<unknown>) => syncReviewScheduleHandler(callerOf(request), request.data, liveDeps()),
);

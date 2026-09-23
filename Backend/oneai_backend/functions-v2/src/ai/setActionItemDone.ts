import { onCall, type CallableRequest } from "firebase-functions/v2/https";
import { liveDeps } from "../lib/deps.js";
import { callerOf } from "../lib/handler.js";
import { setActionItemDoneHandler } from "./handler.js";

export const setActionItemDone = onCall(
  { enforceAppCheck: true, memory: "256MiB", timeoutSeconds: 30, maxInstances: 10 },
  (request: CallableRequest<unknown>) => setActionItemDoneHandler(callerOf(request), request.data, liveDeps()),
);

import { onCall, type CallableRequest } from "firebase-functions/v2/https";
import { liveDeps } from "../lib/deps.js";
import { callerOf } from "../lib/handler.js";
import { deleteGlossaryTermHandler } from "./handler.js";

export const deleteGlossaryTerm = onCall(
  { enforceAppCheck: true, memory: "256MiB", timeoutSeconds: 30 },
  (request: CallableRequest<unknown>) => deleteGlossaryTermHandler(callerOf(request), request.data, liveDeps()),
);

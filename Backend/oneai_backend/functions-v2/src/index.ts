/**
 * setGlobalOptions MUST be the first statement — ES imports are hoisted, so
 * it runs before any function definition is evaluated.
 * This file contains setGlobalOptions plus explicit re-exports and nothing else.
 */
import { setGlobalOptions } from "firebase-functions/v2";

setGlobalOptions({
  region: "asia-southeast1",
  maxInstances: 20,
  memory: "512MiB",
  timeoutSeconds: 60,
});

export { getMe } from "./users/getMe.js";
export { onUserCreated } from "./users/onUserCreated.js";
export { onUserDeleted } from "./users/onUserDeleted.js";

export { createMinute } from "./minutes/createMinute.js";
export { listMinutes } from "./minutes/listMinutes.js";
export { getMinute } from "./minutes/getMinute.js";
export { updateMinute } from "./minutes/updateMinute.js";
export { deleteMinute } from "./minutes/deleteMinute.js";

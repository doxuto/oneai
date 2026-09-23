/** v1 auth trigger — marked explicitly. */
import * as functionsV1 from "firebase-functions/v1";
import { liveDeps } from "../lib/deps.js";
import { wipeUser } from "./lifecycle.js";

export const onUserDeleted = functionsV1
  .region("asia-southeast1")
  .auth.user()
  .onDelete(async (user) => {
    const report = await wipeUser(liveDeps(), user.uid);
    if (!report.firestoreOk || !report.storageOk) {
      // Non-zero exit makes the platform retry the trigger.
      throw new Error(`user delete incomplete for ${user.uid}`);
    }
  });

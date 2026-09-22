/** v1 auth trigger — marked explicitly. */
import * as functionsV1 from "firebase-functions/v1";
import { getBucket, getDb } from "../lib/admin.js";
import { log } from "../lib/logging.js";

export const onUserDeleted = functionsV1
  .region("asia-southeast1")
  .auth.user()
  .onDelete(async (user) => {
    const uid = user.uid;
    const db = getDb();
    const bucket = getBucket();
    let firestoreOk = true;
    let storageOk = true;

    try {
      await db.recursiveDelete(db.doc(`users/${uid}`));
    } catch (err) {
      firestoreOk = false;
      // v1 swallowed this and reported success anyway. Surface it instead.
      log.error("user.delete.firestore_failed", { uid, error: String(err) });
    }

    try {
      await bucket.deleteFiles({ prefix: `users/${uid}/` });
    } catch (err) {
      storageOk = false;
      log.error("user.delete.storage_failed", { uid, error: String(err) });
    }

    log.info("user.deleted", { uid, firestoreOk, storageOk });
    if (!firestoreOk || !storageOk) {
      // Non-zero exit makes the platform retry the trigger.
      throw new Error(`user delete incomplete for ${uid}`);
    }
  });

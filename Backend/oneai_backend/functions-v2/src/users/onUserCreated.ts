/**
 * v1 auth trigger — marked explicitly. There is no v2 equivalent for
 * auth.user().onCreate yet (firebase-functions-pro/project-layout).
 */
import * as functionsV1 from "firebase-functions/v1";
import { FieldValue } from "firebase-admin/firestore";
import { db } from "../lib/admin.js";
import { log } from "../lib/logging.js";
import { periodIdFor } from "../lib/time.js";
import { FREE_DAILY_LIMIT } from "../lib/params.js";

export const onUserCreated = functionsV1
  .region("asia-southeast1")
  .auth.user()
  .onCreate(async (user) => {
    const uid = user.uid;
    const now = new Date();
    const periodId = periodIdFor(now);
    const expiresAt = new Date(now.getTime() + 3 * 24 * 60 * 60 * 1000);

    const batch = db.batch();
    batch.set(db.doc(`users/${uid}`), {
      email: user.email ?? null,
      displayName: user.displayName ?? null,
      photoUrl: user.photoURL ?? null,
      plan: "free",
      planExpiresAt: null,
      minuteCount: 0,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
      lastSeenAt: FieldValue.serverTimestamp(),
    });
    batch.set(db.doc(`users/${uid}/quota/${periodId}`), {
      periodId,
      used: 0,
      baseLimit: FREE_DAILY_LIMIT.value(),
      rewardBonus: 0,
      expiresAt,
    });
    await batch.commit();

    log.info("user.created", { uid, periodId });
  });

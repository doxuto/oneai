/**
 * What the two auth triggers do, as plain functions over `Deps` so the
 * emulator can exercise them. The triggers in onUserCreated.ts /
 * onUserDeleted.ts are glue only.
 */
import { FieldValue } from "firebase-admin/firestore";
import type { Deps } from "../lib/deps.js";
import { log } from "../lib/logging.js";
import { periodIdFor } from "../lib/time.js";

export interface NewUser {
  uid: string;
  email?: string | null;
  displayName?: string | null;
  photoURL?: string | null;
}

/** Quota docs carry a TTL so per-day documents disappear on their own. */
export const QUOTA_TTL_MS = 3 * 24 * 60 * 60 * 1000;

/**
 * Creates `users/{uid}` and today's quota doc. Auth triggers are
 * at-least-once: a redelivery for a user who already exists must NOT reset
 * their profile or today's `used`, so an existing profile is left untouched.
 * Returns whether anything was written.
 */
export async function provisionUser(deps: Deps, user: NewUser): Promise<boolean> {
  const now = deps.now();
  const periodId = periodIdFor(now);
  const userRef = deps.db.doc(`users/${user.uid}`);

  const created = await deps.db.runTransaction(async (tx) => {
    const existing = await tx.get(userRef);
    if (existing.exists) return false;
    tx.set(userRef, {
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
    tx.set(userRef.collection("quota").doc(periodId), {
      periodId,
      used: 0,
      baseLimit: deps.limits.free.dailyLimit,
      rewardBonus: 0,
      expiresAt: new Date(now.getTime() + QUOTA_TTL_MS),
    });
    return true;
  });

  log.info(created ? "user.created" : "user.create.redelivered", { uid: user.uid, periodId });
  return created;
}

export interface WipeReport {
  firestoreOk: boolean;
  storageOk: boolean;
}

/**
 * Removes every document under `users/{uid}` (recursively) and every file
 * under `users/{uid}/`. Each half is attempted even if the other fails, and
 * a partial wipe is reported so the trigger can throw and be retried —
 * v1 swallowed the error and logged success.
 */
export async function wipeUser(deps: Deps, uid: string): Promise<WipeReport> {
  const report: WipeReport = { firestoreOk: true, storageOk: true };
  try {
    await deps.db.recursiveDelete(deps.db.doc(`users/${uid}`));
  } catch (err) {
    report.firestoreOk = false;
    log.error("user.delete.firestore_failed", { uid, error: String(err) });
  }
  try {
    await deps.bucket.deleteFiles({ prefix: `users/${uid}/` });
  } catch (err) {
    report.storageOk = false;
    log.error("user.delete.storage_failed", { uid, error: String(err) });
  }
  log.info("user.deleted", { uid, ...report });
  return report;
}

/**
 * Daily quota. One document per user per Vietnam calendar day:
 *   users/{uid}/quota/{periodId}  { used, baseLimit, rewardBonus, expiresAt }
 *
 * Semantics (docs/06 §1):
 *   allowed  = used < baseLimit + rewardBonus     (premium never blocked, still counted)
 *   reward   RAISES the ceiling; it never lowers `used` — 3/5 + 2 ⇒ 3/7
 *   expiresAt drives a Firestore TTL so old periods vanish on their own
 *
 * Every mutation happens inside the caller's transaction so a check-then-
 * consume can never race — the v1 TOCTOU bug is structurally impossible here.
 */
import { HttpsError } from "firebase-functions/v2/https";
import type { DocumentReference, Firestore, Transaction } from "firebase-admin/firestore";
import type { PlanLimits } from "../lib/deps.js";
import { nextPeriodStart, periodIdFor } from "../lib/time.js";
import type { Plan } from "../users/types.js";

export interface QuotaState {
  periodId: string;
  used: number;
  baseLimit: number;
  rewardBonus: number;
  /** Ceiling actually in force. */
  limit: number;
  resetAt: Date;
}

export const quotaRef = (db: Firestore, uid: string, periodId: string): DocumentReference =>
  db.doc(`users/${uid}/quota/${periodId}`);

/** Pure. */
export function canConsume(state: Pick<QuotaState, "used" | "limit">, plan: Plan): boolean {
  if (plan === "premium") return true;
  return state.used < state.limit;
}

/** Read (or synthesise) today's quota inside a transaction. Never writes. */
export async function readQuota(
  tx: Transaction,
  db: Firestore,
  uid: string,
  limits: PlanLimits,
  now: Date,
): Promise<{ ref: DocumentReference; state: QuotaState; exists: boolean }> {
  const periodId = periodIdFor(now);
  const ref = quotaRef(db, uid, periodId);
  const snap = await tx.get(ref);
  const d = (snap.data() ?? {}) as { used?: number; baseLimit?: number; rewardBonus?: number };
  const used = typeof d.used === "number" ? d.used : 0;
  const baseLimit = typeof d.baseLimit === "number" ? d.baseLimit : limits.dailyLimit;
  const rewardBonus = typeof d.rewardBonus === "number" ? d.rewardBonus : 0;
  return {
    ref,
    exists: snap.exists,
    state: { periodId, used, baseLimit, rewardBonus, limit: baseLimit + rewardBonus, resetAt: nextPeriodStart(now) },
  };
}

/**
 * Check + consume in one transaction step. Throws resource-exhausted with
 * details.limit / details.resetAt when the free ceiling is hit.
 */
export async function consumeQuota(
  tx: Transaction,
  db: Firestore,
  uid: string,
  plan: Plan,
  limits: PlanLimits,
  now: Date,
): Promise<QuotaState> {
  const { ref, state, exists } = await readQuota(tx, db, uid, limits, now);
  if (!canConsume(state, plan)) {
    throw new HttpsError("resource-exhausted", "Daily limit reached", {
      limit: state.limit,
      used: state.used,
      resetAt: state.resetAt.toISOString(),
    });
  }
  const next = { ...state, used: state.used + 1 };
  const expiresAt = new Date(state.resetAt.getTime() + 2 * 24 * 60 * 60 * 1000); // keep 2 days for support
  if (exists) {
    tx.update(ref, { used: next.used });
  } else {
    tx.set(ref, {
      periodId: state.periodId,
      used: next.used,
      baseLimit: state.baseLimit,
      rewardBonus: state.rewardBonus,
      expiresAt,
    });
  }
  return next;
}

/** Give one back (job failed permanently, or cancelled before work started). Floors at 0. */
export async function refundQuota(
  tx: Transaction,
  db: Firestore,
  uid: string,
  periodId: string,
): Promise<void> {
  const ref = quotaRef(db, uid, periodId);
  const snap = await tx.get(ref);
  if (!snap.exists) return;
  const used = (snap.data() as { used?: number }).used ?? 0;
  tx.update(ref, { used: Math.max(0, used - 1) });
}

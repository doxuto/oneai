/**
 * Daily quota, measured in SECONDS of audio. One document per user per
 * Vietnam calendar day:
 *   users/{uid}/quota/{periodId}  { usedSeconds, limitSeconds, aiCalls, expiresAt }
 *
 * Semantics (docs/06 §1, decided 24/09):
 *   free     limitSeconds = FREE_DAILY_SECONDS (600 = 10 minutes/day)
 *   premium  limitSeconds = 0 ⇒ unlimited (still counted for analytics)
 *   a job RESERVES its declared length at start and is SETTLED to the real
 *   length once the worker has measured the file; a PDF costs a flat
 *   `pdfChargeSeconds`. There is no reward bonus any more.
 *   expiresAt drives a Firestore TTL so old periods vanish on their own.
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
  usedSeconds: number;
  /** 0 = unlimited. */
  limitSeconds: number;
  resetAt: Date;
}

export const quotaRef = (db: Firestore, uid: string, periodId: string): DocumentReference =>
  db.doc(`users/${uid}/quota/${periodId}`);

export const remainingSeconds = (s: Pick<QuotaState, "usedSeconds" | "limitSeconds">): number =>
  s.limitSeconds === 0 ? Number.POSITIVE_INFINITY : Math.max(0, s.limitSeconds - s.usedSeconds);

/** Pure. Can `seconds` more be charged? Premium is never blocked. */
export function canConsume(state: Pick<QuotaState, "usedSeconds" | "limitSeconds">, plan: Plan, seconds: number): boolean {
  if (plan === "premium" || state.limitSeconds === 0) return true;
  return state.usedSeconds + seconds <= state.limitSeconds;
}

function exhausted(state: QuotaState, requested: number): HttpsError {
  return new HttpsError("resource-exhausted", "Daily free minutes used up", {
    reason: "quota",
    limitSeconds: state.limitSeconds,
    usedSeconds: state.usedSeconds,
    remainingSeconds: Math.max(0, state.limitSeconds - state.usedSeconds),
    requestedSeconds: requested,
    resetAt: state.resetAt.toISOString(),
  });
}

/** Read (or synthesise) today's quota inside a transaction. Never writes. */
export async function readQuota(
  tx: Transaction,
  db: Firestore,
  uid: string,
  limits: PlanLimits,
  now: Date,
  periodId = periodIdFor(now),
): Promise<{ ref: DocumentReference; state: QuotaState; exists: boolean }> {
  const ref = quotaRef(db, uid, periodId);
  const snap = await tx.get(ref);
  const d = (snap.data() ?? {}) as { usedSeconds?: number; limitSeconds?: number };
  return {
    ref,
    exists: snap.exists,
    state: {
      periodId,
      usedSeconds: typeof d.usedSeconds === "number" ? d.usedSeconds : 0,
      limitSeconds: typeof d.limitSeconds === "number" ? d.limitSeconds : limits.dailySeconds,
      resetAt: nextPeriodStart(now),
    },
  };
}

function write(tx: Transaction, ref: DocumentReference, exists: boolean, state: QuotaState, usedSeconds: number): QuotaState {
  const next = { ...state, usedSeconds };
  if (exists) {
    tx.update(ref, { usedSeconds });
  } else {
    tx.set(ref, {
      periodId: state.periodId,
      usedSeconds,
      limitSeconds: state.limitSeconds,
      expiresAt: new Date(state.resetAt.getTime() + 2 * 24 * 60 * 60 * 1000), // keep 2 days for support
    });
  }
  return next;
}

/**
 * Check + reserve `seconds` in one transaction step. Throws resource-exhausted
 * (details.remainingSeconds / resetAt) when the free ceiling would be crossed.
 */
export async function consumeQuota(
  tx: Transaction,
  db: Firestore,
  uid: string,
  plan: Plan,
  limits: PlanLimits,
  now: Date,
  seconds: number,
): Promise<QuotaState> {
  const { ref, state, exists } = await readQuota(tx, db, uid, limits, now);
  if (!canConsume(state, plan, seconds)) throw exhausted(state, seconds);
  return write(tx, ref, exists, state, state.usedSeconds + seconds);
}

/**
 * Settle a reservation to the measured length: charges the difference, or
 * gives the excess back. A free user whose real file is longer than what is
 * left today is refused here — before any STT money is spent.
 */
export async function settleQuota(
  tx: Transaction,
  db: Firestore,
  uid: string,
  plan: Plan,
  limits: PlanLimits,
  now: Date,
  periodId: string,
  reservedSeconds: number,
  actualSeconds: number,
): Promise<QuotaState> {
  const delta = actualSeconds - reservedSeconds;
  const { ref, state, exists } = await readQuota(tx, db, uid, limits, now, periodId);
  if (delta > 0 && !canConsume(state, plan, delta)) throw exhausted(state, actualSeconds);
  return write(tx, ref, exists, state, Math.max(0, state.usedSeconds + delta));
}

/** Give seconds back (job failed permanently, or cancelled before work started). Floors at 0. */
export async function refundQuota(
  tx: Transaction,
  db: Firestore,
  uid: string,
  periodId: string,
  seconds: number,
): Promise<void> {
  const ref = quotaRef(db, uid, periodId);
  const snap = await tx.get(ref);
  if (!snap.exists) return;
  const used = (snap.data() as { usedSeconds?: number }).usedSeconds ?? 0;
  tx.update(ref, { usedSeconds: Math.max(0, used - seconds) });
}

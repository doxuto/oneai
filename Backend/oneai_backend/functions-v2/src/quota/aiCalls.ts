/**
 * Per-user daily cap on model calls (chat, generate*, mapSpeakers). Lives on
 * the same per-day quota doc as transcription usage, so it expires with it.
 * Cache hits are free — only a real model call counts.
 */
import { HttpsError } from "firebase-functions/v2/https";
import type { Firestore } from "firebase-admin/firestore";
import type { PlanLimits } from "../lib/deps.js";
import { nextPeriodStart, periodIdFor } from "../lib/time.js";
import { quotaRef } from "./quota.js";

export async function consumeAiCall(
  db: Firestore,
  uid: string,
  limits: PlanLimits,
  now: Date,
): Promise<{ used: number; limit: number }> {
  const periodId = periodIdFor(now);
  const ref = quotaRef(db, uid, periodId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const d = (snap.data() ?? {}) as { aiCalls?: number };
    const used = typeof d.aiCalls === "number" ? d.aiCalls : 0;
    if (used >= limits.aiCallsPerDay) {
      throw new HttpsError("resource-exhausted", "Daily AI limit reached", {
        reason: "aiDailyLimit", limit: limits.aiCallsPerDay, used, resetAt: nextPeriodStart(now).toISOString(),
      });
    }
    if (snap.exists) {
      tx.update(ref, { aiCalls: used + 1 });
    } else {
      tx.set(ref, {
        periodId, usedSeconds: 0, limitSeconds: limits.dailySeconds, aiCalls: 1,
        expiresAt: new Date(nextPeriodStart(now).getTime() + 2 * 24 * 60 * 60 * 1000),
      });
    }
    return { used: used + 1, limit: limits.aiCallsPerDay };
  });
}

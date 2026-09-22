import { FieldValue, Timestamp } from "firebase-admin/firestore";
import type { Deps } from "../lib/deps.js";
import { log } from "../lib/logging.js";
import { periodIdFor } from "../lib/time.js";
import { quotaRef } from "../quota/quota.js";
import { clampGrant, keyStore, parsePayload, splitSigned, verifySignature, TX_RETENTION_DAYS } from "./verify.js";

export type SsvResult = { status: 200 | 400 | 403 | 500; body: string; granted?: number };

/**
 * Status codes ARE the contract (rewarded-ssv.md):
 *   empty query → 200 (the console's "Verify URL" sends one)
 *   missing user_id / unparseable → 400, grant nothing
 *   keys unavailable → 500 so Google retries
 *   bad signature → 403
 *   success or already processed → 200
 */
export async function handleSsv(rawQuery: string, deps: Deps, keys: ReturnType<typeof keyStore>): Promise<SsvResult> {
  if (!rawQuery) return { status: 200, body: "ok" };

  const split = splitSigned(rawQuery);
  if (!split) return { status: 400, body: "bad request" };
  const payload = parsePayload(split.message);
  if (!payload) return { status: 400, body: "bad request" };

  let pem: string | null;
  try {
    pem = await keys.pemFor(split.keyId);
  } catch (err) {
    log.error("ssv.keys_unavailable", { error: String(err) });
    return { status: 500, body: "keys unavailable" };
  }
  if (!pem || !verifySignature(split.message, split.signature, pem)) {
    log.warn("ssv.bad_signature", { transactionId: payload.transactionId, keyId: split.keyId });
    return { status: 403, body: "invalid signature" };
  }

  const amount = clampGrant(payload.rewardAmount);
  const now = deps.now();
  const txRef = deps.db.doc(`adRewards/${payload.transactionId}`);
  try {
    const granted = await deps.db.runTransaction(async (tx) => {
      if ((await tx.get(txRef)).exists) return false;
      if (amount > 0) {
        // Grant RAISES the ceiling on the current period; it never lowers `used`.
        const qRef = quotaRef(deps.db, payload.userId, periodIdFor(now));
        const q = await tx.get(qRef);
        if (q.exists) {
          tx.update(qRef, { rewardBonus: FieldValue.increment(amount) });
        } else {
          const plan = ((await tx.get(deps.db.doc(`users/${payload.userId}`))).data() as { plan?: string } | undefined)?.plan;
          const base = plan === "premium" ? deps.limits.premium.dailyLimit : deps.limits.free.dailyLimit;
          tx.set(qRef, { periodId: periodIdFor(now), used: 0, baseLimit: base, rewardBonus: amount, expiresAt: new Date(now.getTime() + 3 * 24 * 3600 * 1000) });
        }
      }
      tx.create(txRef, {
        uid: payload.userId, amount, adUnit: payload.adUnit, adNetwork: payload.adNetwork, rewardItem: payload.rewardItem,
        at: FieldValue.serverTimestamp(), expiresAt: Timestamp.fromMillis(now.getTime() + TX_RETENTION_DAYS * 24 * 3600 * 1000),
      });
      return true;
    });
    log.info(granted ? "ssv.granted" : "ssv.duplicate", { uid: payload.userId, amount, transactionId: payload.transactionId });
    return { status: 200, body: "ok", granted: granted ? amount : 0 };
  } catch (err) {
    log.error("ssv.grant_failed", { uid: payload.userId, transactionId: payload.transactionId, error: String(err) });
    return { status: 500, body: "grant failed" };
  }
}

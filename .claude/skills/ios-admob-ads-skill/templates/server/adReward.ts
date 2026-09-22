/**
 * AdMob rewarded-ad server-side verification (SSV) callback — Firebase Functions v2.
 *
 * The client never credits a reward. Google calls this endpoint; we verify Google's signature
 * over the raw query string, consume transaction_id exactly once, then apply the grant.
 *
 * Adapt `applyGrant` to the app's quota/wallet model. Everything else is app-agnostic.
 *
 * Deploy, then set the URL as the SSV callback on the rewarded ad unit in the AdMob console.
 * The function is public on purpose: Google has no Firebase credentials. The signature is the auth.
 */
import { createPublicKey, verify, type KeyObject } from "node:crypto";
import { onRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";
import { getFirestore, Timestamp, type Transaction } from "firebase-admin/firestore";

const KEYS_URL = "https://www.gstatic.com/admob/reward/verifier-keys.json";
const KEY_CACHE_MS = 24 * 60 * 60 * 1000;
/** Server-side ceiling, whatever the AdMob console says. */
const MAX_GRANT = 5;
/** How long to keep consumed transaction ids (enable a Firestore TTL policy on `expiresAt`). */
const TX_RETENTION_DAYS = 30;

// ---------------------------------------------------------------------------------------------
// Pure verification (unit-testable without Firebase)
// ---------------------------------------------------------------------------------------------

export interface SsvPayload {
  adNetwork?: string;
  adUnit?: string;
  customData?: string;
  keyId: string;
  rewardAmount: number;
  rewardItem?: string;
  timestamp: number;
  transactionId: string;
  userId?: string;
}

/**
 * Splits the raw query string into the signed message and the signature.
 * The message is everything before "&signature=" — cut as a string, never parsed and re-encoded,
 * because re-encoding (e.g. "%2F" → "/") changes the bytes Google signed.
 */
export function splitSigned(rawQuery: string): { message: string; signature: string } | null {
  const q = rawQuery.startsWith("?") ? rawQuery.slice(1) : rawQuery;
  const marker = "&signature=";
  const at = q.indexOf(marker);
  if (at < 0) return null;
  const message = q.slice(0, at);
  const rest = q.slice(at + marker.length);
  const signature = rest.split("&")[0];
  return signature ? { message, signature: decodeURIComponent(signature) } : null;
}

export function parsePayload(rawQuery: string): SsvPayload | null {
  const p = new URLSearchParams(rawQuery.startsWith("?") ? rawQuery.slice(1) : rawQuery);
  const keyId = p.get("key_id");
  const transactionId = p.get("transaction_id");
  const timestamp = Number(p.get("timestamp"));
  if (!keyId || !transactionId || !Number.isFinite(timestamp)) return null;
  return {
    adNetwork: p.get("ad_network") ?? undefined,
    adUnit: p.get("ad_unit") ?? undefined,
    customData: p.get("custom_data") ?? undefined,
    keyId,
    rewardAmount: Number(p.get("reward_amount") ?? "0"),
    rewardItem: p.get("reward_item") ?? undefined,
    timestamp,
    transactionId,
    userId: p.get("user_id") ?? undefined,
  };
}

/** Google's signature is URL-safe base64 of a DER-encoded ECDSA P-256 / SHA-256 signature. */
export function verifySignature(message: string, signatureB64Url: string, key: KeyObject): boolean {
  const b64 = signatureB64Url.replace(/-/g, "+").replace(/_/g, "/");
  const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
  const sig = Buffer.from(padded, "base64");
  return verify("sha256", Buffer.from(message, "utf8"), { key, dsaEncoding: "der" }, sig);
}

// ---------------------------------------------------------------------------------------------
// Key cache
// ---------------------------------------------------------------------------------------------

let keyCache: { at: number; keys: Map<string, KeyObject> } | null = null;

async function fetchKeys(): Promise<Map<string, KeyObject>> {
  const res = await fetch(KEYS_URL);
  if (!res.ok) throw new Error(`verifier keys HTTP ${res.status}`);
  const body = (await res.json()) as { keys: { keyId: number | string; pem: string }[] };
  const keys = new Map<string, KeyObject>();
  for (const k of body.keys ?? []) keys.set(String(k.keyId), createPublicKey(k.pem));
  if (keys.size === 0) throw new Error("verifier keys empty");
  keyCache = { at: Date.now(), keys };
  return keys;
}

async function keyFor(keyId: string): Promise<KeyObject | undefined> {
  const fresh = keyCache && Date.now() - keyCache.at < KEY_CACHE_MS;
  let keys = fresh ? keyCache!.keys : await fetchKeys();
  if (!keys.has(keyId) && fresh) keys = await fetchKeys(); // key rotation
  return keys.get(keyId);
}

// ---------------------------------------------------------------------------------------------
// App-specific grant — ADAPT THIS
// ---------------------------------------------------------------------------------------------

/**
 * Apply the reward inside the same transaction that consumed the transaction id.
 * Recommended semantics: raise the *ceiling* of the user's current quota period
 * (3/5 used + 2 → 3/7), stored on that period's document so it expires with the period.
 */
async function applyGrant(tx: Transaction, uid: string, amount: number, payload: SsvPayload): Promise<void> {
  const db = getFirestore();
  const period = new Date().toISOString().slice(0, 10); // e.g. daily periods, UTC
  const ref = db.doc(`users/${uid}/quota/${period}`);
  const snap = await tx.get(ref);
  const bonus = (snap.get("rewardBonus") as number | undefined) ?? 0;
  tx.set(ref, { rewardBonus: bonus + amount, updatedAt: Timestamp.now() }, { merge: true });
  void payload;
}

// ---------------------------------------------------------------------------------------------
// HTTP handler
// ---------------------------------------------------------------------------------------------

export const adReward = onRequest({ region: "us-central1", cors: false }, async (req, res) => {
  const rawQuery = req.originalUrl.includes("?") ? req.originalUrl.slice(req.originalUrl.indexOf("?") + 1) : "";

  // AdMob console "Verify URL" sends a request with no parameters; answer 200 so it can save.
  if (!rawQuery) {
    res.status(200).send("ok");
    return;
  }

  const signed = splitSigned(rawQuery);
  const payload = parsePayload(rawQuery);
  if (!signed || !payload) {
    res.status(400).send("bad request");
    return;
  }

  let key: KeyObject | undefined;
  try {
    key = await keyFor(payload.keyId);
  } catch (err) {
    // 500 so Google retries. Returning 200 here would silently swallow the reward.
    logger.error("adReward: cannot load verifier keys", err);
    res.status(500).send("keys unavailable");
    return;
  }
  if (!key || !verifySignature(signed.message, signed.signature, key)) {
    logger.warn("adReward: invalid signature", { tx: payload.transactionId });
    res.status(403).send("invalid signature");
    return;
  }

  const uid = payload.userId;
  if (!uid) {
    res.status(400).send("missing user_id");
    return;
  }
  const amount = Math.max(0, Math.min(MAX_GRANT, Math.floor(payload.rewardAmount || 0)));

  const db = getFirestore();
  const txRef = db.doc(`adRewards/${payload.transactionId}`);
  try {
    const granted = await db.runTransaction(async (tx) => {
      const seen = await tx.get(txRef);
      if (seen.exists) return false; // Google retries on timeout: consume once.
      await applyGrant(tx, uid, amount, payload);
      tx.create(txRef, {
        uid,
        amount,
        adUnit: payload.adUnit ?? null,
        at: Timestamp.now(),
        expiresAt: Timestamp.fromMillis(Date.now() + TX_RETENTION_DAYS * 86_400_000),
      });
      return true;
    });
    logger.info("adReward", { tx: payload.transactionId, granted, amount });
    res.status(200).send("ok");
  } catch (err) {
    logger.error("adReward: grant failed", err);
    res.status(500).send("error");
  }
});

/**
 * AdMob rewarded server-side verification (ios-admob-ads-skill/rewarded-ssv).
 *
 *   "The client never credits a reward. An app that accepts 'I just watched
 *    an ad, give me more' accepts it from anyone."
 *
 * Google signs the query string (everything before `&signature=`) with an
 * ECDSA P-256 key; we verify against the published key set. The message is
 * cut as a raw string, never parsed and re-encoded — re-encoding (e.g. %2F →
 * /) changes the bytes that were signed.
 */
import { createPublicKey, verify as cryptoVerify } from "node:crypto";
import { log } from "../lib/logging.js";

export const KEYS_URL = "https://www.gstatic.com/admob/reward/verifier-keys.json";
export const KEY_CACHE_MS = 24 * 60 * 60 * 1000;
/** Clamp regardless of what the console says. */
export const MAX_GRANT = 5;
export const TX_RETENTION_DAYS = 30;

export interface VerifierKey { keyId: number; pem: string }
export interface KeySet { keys: VerifierKey[]; fetchedAt: number }

export interface SsvPayload {
  adNetwork: string;
  adUnit: string;
  customData: string | null;
  keyId: number;
  rewardAmount: number;
  rewardItem: string;
  timestamp: number;
  transactionId: string;
  userId: string;
}

/** Split the raw query at the literal `&signature=` marker. */
export function splitSigned(rawQuery: string): { message: string; signature: string; keyId: number } | null {
  const idx = rawQuery.indexOf("&signature=");
  if (idx < 0) return null;
  const message = rawQuery.slice(0, idx);
  const rest = rawQuery.slice(idx + "&signature=".length);
  const [signature] = rest.split("&");
  const keyIdMatch = /(?:^|&)key_id=(\d+)(?:&|$)/.exec(message);
  if (!signature || !keyIdMatch) return null;
  return { message, signature, keyId: Number.parseInt(keyIdMatch[1] ?? "0", 10) };
}

export function parsePayload(message: string): SsvPayload | null {
  const p = new URLSearchParams(message);
  const userId = p.get("user_id");
  const transactionId = p.get("transaction_id");
  const keyId = Number.parseInt(p.get("key_id") ?? "", 10);
  if (!userId || !transactionId || !Number.isFinite(keyId)) return null;
  return {
    adNetwork: p.get("ad_network") ?? "",
    adUnit: p.get("ad_unit") ?? "",
    customData: p.get("custom_data"),
    keyId,
    rewardAmount: Number.parseFloat(p.get("reward_amount") ?? "0") || 0,
    rewardItem: p.get("reward_item") ?? "",
    timestamp: Number.parseInt(p.get("timestamp") ?? "0", 10) || 0,
    transactionId,
    userId,
  };
}

/** URL-safe base64 → standard, padded. */
export function decodeSignature(sig: string): Buffer {
  const std = sig.replace(/-/g, "+").replace(/_/g, "/");
  const pad = std.length % 4 === 0 ? "" : "=".repeat(4 - (std.length % 4));
  return Buffer.from(std + pad, "base64");
}

export function verifySignature(message: string, signature: string, pem: string): boolean {
  try {
    const key = createPublicKey(pem);
    return cryptoVerify("sha256", Buffer.from(message, "utf8"), { key, dsaEncoding: "der" }, decodeSignature(signature));
  } catch (err) {
    log.warn("ssv.verify_error", { error: String(err) });
    return false;
  }
}

export function clampGrant(amount: number): number {
  return Math.max(0, Math.min(MAX_GRANT, Math.floor(Number.isFinite(amount) ? amount : 0)));
}

/** Fetch + cache the key set; refetch once on an unknown key id (rotation). */
export function keyStore(fetchImpl: typeof fetch = fetch, now: () => number = Date.now) {
  let cache: KeySet | null = null;
  async function load(): Promise<KeySet> {
    const res = await fetchImpl(KEYS_URL);
    if (!res.ok) throw new Error(`verifier-keys ${res.status}`);
    const json = (await res.json()) as { keys?: { keyId: number; pem: string }[] };
    cache = { keys: (json.keys ?? []).map((k) => ({ keyId: Number(k.keyId), pem: k.pem })), fetchedAt: now() };
    return cache;
  }
  return {
    async pemFor(keyId: number): Promise<string | null> {
      if (!cache || now() - cache.fetchedAt > KEY_CACHE_MS) await load();
      let k = cache!.keys.find((x) => x.keyId === keyId);
      if (!k) { await load(); k = cache!.keys.find((x) => x.keyId === keyId); }
      return k?.pem ?? null;
    },
  };
}

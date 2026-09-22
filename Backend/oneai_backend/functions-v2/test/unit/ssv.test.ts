import { describe, expect, it } from "vitest";
import { clampGrant, keyStore, parsePayload, splitSigned, verifySignature } from "../../src/ads/verify.js";
import { makeSigner } from "../helpers/ssv.js";

const base = { ad_network: "5450213213286189855", ad_unit: "1234", reward_amount: "1", reward_item: "credit", timestamp: "1790000000000", transaction_id: "tx-1", user_id: "u1" };

describe("splitSigned / parsePayload", () => {
  it("cuts at the literal &signature= and reads key_id", () => {
    const s = makeSigner();
    const q = s.query(base);
    const split = splitSigned(q)!;
    expect(split.keyId).toBe(s.keyId);
    expect(split.message.endsWith(`key_id=${s.keyId}`)).toBe(true);
    expect(parsePayload(split.message)).toMatchObject({ userId: "u1", transactionId: "tx-1", rewardAmount: 1 });
  });
  it("no signature → null", () => expect(splitSigned("a=1&b=2")).toBeNull());
  it("missing user_id → null", () => expect(parsePayload("transaction_id=t&key_id=1")).toBeNull());
});

describe("verifySignature", () => {
  it("accepts a valid signature, including %2F in custom_data untouched", () => {
    const s = makeSigner();
    const q = s.query({ ...base, custom_data: "a/b c" });
    const split = splitSigned(q)!;
    expect(split.message).toContain("custom_data=a%2Fb+c");
    expect(verifySignature(split.message, split.signature, s.pem)).toBe(true);
  });
  it("rejects a tampered reward_amount", () => {
    const s = makeSigner();
    const q = s.query(base).replace("reward_amount=1", "reward_amount=999");
    const split = splitSigned(q)!;
    expect(verifySignature(split.message, split.signature, s.pem)).toBe(false);
  });
  it("rejects a signature from another key", () => {
    const a = makeSigner(); const b = makeSigner();
    const split = splitSigned(a.query(base))!;
    expect(verifySignature(split.message, split.signature, b.pem)).toBe(false);
  });
  it("garbage is false, not a throw", () => expect(verifySignature("m", "!!!", "not a pem")).toBe(false));
});

describe("clampGrant", () => {
  it("clamps to [0, MAX_GRANT] and floors", () => {
    expect(clampGrant(999)).toBe(5);
    expect(clampGrant(2.9)).toBe(2);
    expect(clampGrant(-1)).toBe(0);
    expect(clampGrant(Number.NaN)).toBe(0);
  });
});

describe("keyStore", () => {
  it("caches for 24h and refetches once on an unknown key id", async () => {
    let calls = 0;
    const s1 = makeSigner(1); const s2 = makeSigner(2);
    const fetchImpl: typeof fetch = async () => { calls++; return new Response(JSON.stringify({ keys: calls === 1 ? [{ keyId: 1, pem: s1.pem }] : [{ keyId: 1, pem: s1.pem }, { keyId: 2, pem: s2.pem }] }), { status: 200 }); };
    let t = 0;
    const ks = keyStore(fetchImpl, () => t);
    expect(await ks.pemFor(1)).toBe(s1.pem); expect(calls).toBe(1);
    expect(await ks.pemFor(1)).toBe(s1.pem); expect(calls).toBe(1);   // cached
    expect(await ks.pemFor(2)).toBe(s2.pem); expect(calls).toBe(2);   // rotation → refetch once
    t = 25 * 3600 * 1000;
    await ks.pemFor(1); expect(calls).toBe(3);                          // expired
  });
  it("propagates a fetch failure so the caller can answer 500", async () => {
    const ks = keyStore(async () => new Response("nope", { status: 503 }));
    await expect(ks.pemFor(1)).rejects.toThrow();
  });
});

/** Runs under `npm run test:integration`. The five required SSV tests from ios-admob-ads-skill. */
import { beforeEach, describe, expect, it } from "vitest";
import { handleSsv } from "../../src/ads/reward.js";
import { keyStore } from "../../src/ads/verify.js";
import { unitDeps } from "../../src/lib/deps.js";
import { clearFirestore, fixedNow, testDb } from "../helpers/emulator.js";
import { makeSigner } from "../helpers/ssv.js";

const db = testDb();
const deps = unitDeps({ db, now: fixedNow() }); // 2026-09-23 10:00 VN
const base = { ad_network: "n", ad_unit: "unit-1", reward_amount: "2", reward_item: "credit", timestamp: "1", transaction_id: "tx-1", user_id: "u1" };

describe("adRewardSsv", () => {
  beforeEach(async () => { await clearFirestore(); await db.doc("users/u1").set({ plan: "free" }); await db.doc("users/u1/quota/2026-09-23").set({ used: 1, baseLimit: 1, rewardBonus: 0 }); });

  it("1. a valid signature with %2F in custom_data verifies and raises the ceiling (1/1 → 1/3)", async () => {
    const s = makeSigner();
    const r = await handleSsv(s.query({ ...base, custom_data: "ctx/1" }), deps, keyStore(s.fetchKeys));
    expect(r).toMatchObject({ status: 200, granted: 2 });
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()).toMatchObject({ used: 1, rewardBonus: 2 });
    expect((await db.doc("adRewards/tx-1").get()).data()).toMatchObject({ uid: "u1", amount: 2, adUnit: "unit-1" });
  });

  it("2. a tampered reward_amount fails with 403 and grants nothing", async () => {
    const s = makeSigner();
    const q = s.query(base).replace("reward_amount=2", "reward_amount=5");
    expect((await handleSsv(q, deps, keyStore(s.fetchKeys))).status).toBe(403);
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.rewardBonus).toBe(0);
    expect((await db.doc("adRewards/tx-1").get()).exists).toBe(false);
  });

  it("3. the same transaction_id twice grants once; both answer 200", async () => {
    const s = makeSigner(); const ks = keyStore(s.fetchKeys);
    const q = s.query(base);
    expect(await handleSsv(q, deps, ks)).toMatchObject({ status: 200, granted: 2 });
    expect(await handleSsv(q, deps, ks)).toMatchObject({ status: 200, granted: 0 });
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.rewardBonus).toBe(2);
  });

  it("4. key fetch failure answers 500 so Google retries", async () => {
    const s = makeSigner();
    const r = await handleSsv(s.query(base), deps, keyStore(async () => new Response("x", { status: 503 })));
    expect(r.status).toBe(500);
  });

  it("5. missing user_id answers 400 and grants nothing", async () => {
    const s = makeSigner();
    const noUser: Record<string, string> = { ...base };
    delete noUser.user_id;
    const r = await handleSsv(s.query(noUser), deps, keyStore(s.fetchKeys));
    expect(r.status).toBe(400);
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.rewardBonus).toBe(0);
  });

  it("the console's empty 'Verify URL' probe answers 200", async () => {
    expect((await handleSsv("", deps, keyStore(async () => new Response("", { status: 500 })))).status).toBe(200);
  });

  it("amount is clamped server-side whatever the console says", async () => {
    const s = makeSigner();
    const r = await handleSsv(s.query({ ...base, reward_amount: "50" }), deps, keyStore(s.fetchKeys));
    expect(r.granted).toBe(5);
  });

  it("creates today's quota doc when the user has not used the app yet today", async () => {
    await db.doc("users/u1/quota/2026-09-23").delete();
    const s = makeSigner();
    await handleSsv(s.query(base), deps, keyStore(s.fetchKeys));
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()).toMatchObject({ used: 0, baseLimit: 1, rewardBonus: 2 });
  });
});

/** Runs under `npm run test:integration`. */
import { beforeEach, describe, expect, it } from "vitest";
import { consumeQuota, refundQuota } from "../../src/quota/quota.js";
import { clearFirestore, testDb } from "../helpers/emulator.js";

const db = testDb();
const now = new Date("2026-09-23T03:00:00.000Z"); // 10:00 VN → period 2026-09-23
const free = { dailyLimit: 1, maxDurationSeconds: 1800 };

describe("consumeQuota in a transaction", () => {
  beforeEach(() => clearFirestore());

  it("creates today's period on first use and counts it", async () => {
    const state = await db.runTransaction((tx) => consumeQuota(tx, db, "u1", "free", free, now));
    expect(state).toMatchObject({ periodId: "2026-09-23", used: 1, limit: 1 });
    const doc = (await db.doc("users/u1/quota/2026-09-23").get()).data();
    expect(doc).toMatchObject({ used: 1, baseLimit: 1, rewardBonus: 0 });
    expect(doc?.expiresAt).toBeDefined();
  });

  it("second free use today is resource-exhausted with resetAt", async () => {
    await db.runTransaction((tx) => consumeQuota(tx, db, "u1", "free", free, now));
    await expect(
      db.runTransaction((tx) => consumeQuota(tx, db, "u1", "free", free, now)),
    ).rejects.toMatchObject({
      code: "resource-exhausted",
      details: { limit: 1, used: 1, resetAt: "2026-09-23T17:00:00.000Z" },
    });
    // and nothing was written by the failed attempt
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.used).toBe(1);
  });

  it("20 concurrent free attempts with limit 1 let exactly one through", async () => {
    const results = await Promise.allSettled(
      Array.from({ length: 20 }, () =>
        db.runTransaction((tx) => consumeQuota(tx, db, "u1", "free", free, now)),
      ),
    );
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.used).toBe(1);
  });

  it("rewardBonus written by SSV raises the ceiling", async () => {
    await db.doc("users/u1/quota/2026-09-23").set({ used: 1, baseLimit: 1, rewardBonus: 2 });
    const s = await db.runTransaction((tx) => consumeQuota(tx, db, "u1", "free", free, now));
    expect(s).toMatchObject({ used: 2, limit: 3 });
  });

  it("premium is counted but never blocked", async () => {
    for (let i = 0; i < 3; i++) {
      await db.runTransaction((tx) => consumeQuota(tx, db, "u1", "premium", { dailyLimit: 50, maxDurationSeconds: 1 }, now));
    }
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.used).toBe(3);
  });

  it("refund floors at zero and is a no-op when the period does not exist", async () => {
    await db.runTransaction((tx) => consumeQuota(tx, db, "u1", "free", free, now));
    await db.runTransaction((tx) => refundQuota(tx, db, "u1", "2026-09-23"));
    await db.runTransaction((tx) => refundQuota(tx, db, "u1", "2026-09-23"));
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.used).toBe(0);
    await db.runTransaction((tx) => refundQuota(tx, db, "u1", "2020-01-01")); // does not throw
  });

  it("a new VN day is a new period", async () => {
    await db.runTransaction((tx) => consumeQuota(tx, db, "u1", "free", free, now));
    const tomorrow = new Date("2026-09-23T18:00:00.000Z"); // 01:00 24/09 VN
    const s = await db.runTransaction((tx) => consumeQuota(tx, db, "u1", "free", free, tomorrow));
    expect(s.periodId).toBe("2026-09-24");
    expect(s.used).toBe(1);
  });
});

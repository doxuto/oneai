/** Runs under `npm run test:integration`. */
import { beforeEach, describe, expect, it } from "vitest";
import { consumeQuota, refundQuota, settleQuota } from "../../src/quota/quota.js";
import { clearFirestore, testDb } from "../helpers/emulator.js";

const db = testDb();
const now = new Date("2026-09-23T03:00:00.000Z"); // 10:00 VN → period 2026-09-23
const free = { dailySeconds: 600, pdfChargeSeconds: 300, maxDurationSeconds: 600, aiCallsPerDay: 3, maxActiveJobs: 1, sourceRetentionDays: 7 };
const premium = { ...free, dailySeconds: 0, maxDurationSeconds: 14400 };
const used = async () => (await db.doc("users/u1/quota/2026-09-23").get()).data()?.usedSeconds;

describe("consumeQuota in a transaction (seconds per day)", () => {
  beforeEach(() => clearFirestore());

  it("creates today's period on first use and reserves the seconds", async () => {
    const state = await db.runTransaction((tx) => consumeQuota(tx, db, "u1", "free", free, now, 120));
    expect(state).toMatchObject({ periodId: "2026-09-23", usedSeconds: 120, limitSeconds: 600 });
    const doc = (await db.doc("users/u1/quota/2026-09-23").get()).data();
    expect(doc).toMatchObject({ usedSeconds: 120, limitSeconds: 600 });
    expect(doc?.expiresAt).toBeDefined();
  });

  it("crossing the ceiling is resource-exhausted with what is left; nothing is written", async () => {
    await db.runTransaction((tx) => consumeQuota(tx, db, "u1", "free", free, now, 500));
    await expect(db.runTransaction((tx) => consumeQuota(tx, db, "u1", "free", free, now, 101))).rejects.toMatchObject({
      code: "resource-exhausted",
      details: { reason: "quota", limitSeconds: 600, usedSeconds: 500, remainingSeconds: 100, requestedSeconds: 101, resetAt: "2026-09-23T17:00:00.000Z" },
    });
    expect(await used()).toBe(500);
    // exactly the remainder still fits
    await db.runTransaction((tx) => consumeQuota(tx, db, "u1", "free", free, now, 100));
    expect(await used()).toBe(600);
  });

  it("20 concurrent 400-second attempts against 600 let exactly one through", async () => {
    const results = await Promise.allSettled(Array.from({ length: 20 }, () => db.runTransaction((tx) => consumeQuota(tx, db, "u1", "free", free, now, 400))));
    expect(results.filter((r) => r.status === "fulfilled")).toHaveLength(1);
    expect(await used()).toBe(400);
  });

  it("premium (limit 0) is counted but never blocked", async () => {
    for (let i = 0; i < 3; i++) await db.runTransaction((tx) => consumeQuota(tx, db, "u1", "premium", premium, now, 5000));
    expect(await used()).toBe(15000);
  });

  it("settle charges the difference, refunds the excess, and refuses a free overrun", async () => {
    await db.runTransaction((tx) => consumeQuota(tx, db, "u1", "free", free, now, 60));
    await db.runTransaction((tx) => settleQuota(tx, db, "u1", "free", free, now, "2026-09-23", 60, 250));
    expect(await used()).toBe(250);
    await db.runTransaction((tx) => settleQuota(tx, db, "u1", "free", free, now, "2026-09-23", 250, 100));
    expect(await used()).toBe(100);
    await expect(db.runTransaction((tx) => settleQuota(tx, db, "u1", "free", free, now, "2026-09-23", 100, 700))).rejects.toMatchObject({ code: "resource-exhausted", details: { requestedSeconds: 700 } });
    expect(await used()).toBe(100);
  });

  it("refund floors at zero and is a no-op when the period does not exist", async () => {
    await db.runTransaction((tx) => consumeQuota(tx, db, "u1", "free", free, now, 60));
    await db.runTransaction((tx) => refundQuota(tx, db, "u1", "2026-09-23", 60));
    await db.runTransaction((tx) => refundQuota(tx, db, "u1", "2026-09-23", 60));
    expect(await used()).toBe(0);
    await db.runTransaction((tx) => refundQuota(tx, db, "u1", "2020-01-01", 60)); // does not throw
  });

  it("a new VN day is a new period", async () => {
    await db.runTransaction((tx) => consumeQuota(tx, db, "u1", "free", free, now, 600));
    const tomorrow = new Date("2026-09-23T18:00:00.000Z"); // 01:00 24/09 VN
    const s = await db.runTransaction((tx) => consumeQuota(tx, db, "u1", "free", free, tomorrow, 60));
    expect(s.periodId).toBe("2026-09-24");
    expect(s.usedSeconds).toBe(60);
  });
});

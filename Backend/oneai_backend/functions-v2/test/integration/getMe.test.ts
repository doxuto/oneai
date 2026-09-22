/** Runs under `npm run test:integration` (firebase emulators:exec). */
import { Timestamp } from "firebase-admin/firestore";
import { beforeEach, describe, expect, it } from "vitest";
import { unitDeps } from "../../src/lib/deps.js";
import { getMeHandler } from "../../src/users/handler.js";
import { clearFirestore, fixedNow, testDb } from "../helpers/emulator.js";

const db = testDb();
const deps = unitDeps({ db, now: fixedNow("2026-09-23T03:00:00.000Z") }); // 10:00 VN
const client = { appVersion: "2.0.0", build: 1, platform: "ios" as const };
const caller = { uid: "u1", signInProvider: "google.com" };

describe("getMeHandler", () => {
  beforeEach(() => clearFirestore());

  it("is not-found until onUserCreated has written the profile", async () => {
    await expect(getMeHandler(caller, { client }, deps)).rejects.toMatchObject({
      code: "not-found",
    });
  });

  it("returns profile + today's quota, with resetAt at the next VN midnight", async () => {
    await db.doc("users/u1").set({
      email: "a@b.c",
      plan: "free",
      minuteCount: 3,
      createdAt: Timestamp.fromDate(new Date("2026-09-01T00:00:00Z")),
    });
    await db.doc("users/u1/quota/2026-09-23").set({ used: 1, baseLimit: 1, rewardBonus: 2 });

    const out = await getMeHandler(caller, { client }, deps);
    expect(out.user).toMatchObject({ id: "u1", email: "a@b.c", plan: "free", minuteCount: 3 });
    expect(out.user.createdAt).toBe("2026-09-01T00:00:00.000Z");
    expect(out.quota).toEqual({
      used: 1,
      limit: 3, // baseLimit 1 + rewardBonus 2 — reward RAISES the ceiling
      rewardBonus: 2,
      resetAt: "2026-09-23T17:00:00.000Z", // 00:00 24/09 Asia/Ho_Chi_Minh
    });
  });

  it("falls back to the plan's default limit when no quota doc exists yet", async () => {
    await db.doc("users/u1").set({ plan: "premium", planExpiresAt: null });
    const out = await getMeHandler(caller, { client }, deps);
    expect(out.user.plan).toBe("premium");
    expect(out.quota).toMatchObject({ used: 0, limit: 50, rewardBonus: 0 });
  });

  it("downgrades an expired premium to free at read time", async () => {
    await db.doc("users/u1").set({
      plan: "premium",
      planExpiresAt: Timestamp.fromDate(new Date("2026-09-01T00:00:00Z")),
    });
    const out = await getMeHandler(caller, { client }, deps);
    expect(out.user.plan).toBe("free");
    expect(out.quota.limit).toBe(1);
  });

  it("never reads another user's document", async () => {
    await db.doc("users/u2").set({ plan: "premium", planExpiresAt: null });
    await expect(getMeHandler(caller, { client }, deps)).rejects.toMatchObject({
      code: "not-found",
    });
  });
});

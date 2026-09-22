/** Runs under `npm run test:integration`. */
import { Timestamp } from "firebase-admin/firestore";
import { beforeEach, describe, expect, it } from "vitest";
import { handleRevenueCat } from "../../src/billing/revenuecat.js";
import { unitDeps } from "../../src/lib/deps.js";
import { clearFirestore, fixedNow, testDb } from "../helpers/emulator.js";

const db = testDb();
const deps = unitDeps({ db, now: fixedNow() });
const ev = (type: string, extra: Record<string, unknown> = {}) => ({ event: { type, app_user_id: "u1", entitlement_ids: ["pro"], ...extra } });

describe("handleRevenueCat", () => {
  beforeEach(async () => { await clearFirestore(); await db.doc("users/u1").set({ plan: "free", planExpiresAt: null }); });

  it("INITIAL_PURCHASE grants premium with the expiry", async () => {
    const r = await handleRevenueCat(ev("INITIAL_PURCHASE", { expiration_at_ms: Date.UTC(2026, 11, 1) }), deps);
    expect(r.status).toBe(200);
    const u = (await db.doc("users/u1").get()).data()!;
    expect(u.plan).toBe("premium");
    expect((u.planExpiresAt as Timestamp).toDate().toISOString()).toBe("2026-12-01T00:00:00.000Z");
  });

  it("EXPIRATION revokes", async () => {
    await db.doc("users/u1").set({ plan: "premium", planExpiresAt: Timestamp.now() });
    await handleRevenueCat(ev("EXPIRATION"), deps);
    expect((await db.doc("users/u1").get()).data()?.plan).toBe("free");
  });

  it("CANCELLATION keeps premium (access lasts until EXPIRATION) but records the expiry", async () => {
    await db.doc("users/u1").set({ plan: "premium", planExpiresAt: null });
    await handleRevenueCat(ev("CANCELLATION", { expiration_at_ms: Date.UTC(2026, 10, 1) }), deps);
    const u = (await db.doc("users/u1").get()).data()!;
    expect(u.plan).toBe("premium");
    expect(u.planExpiresAt).not.toBeNull();
  });

  it("an unknown user is 404, not a crash and not a new doc (v1 threw on update())", async () => {
    const r = await handleRevenueCat({ event: { type: "RENEWAL", app_user_id: "nobody" } }, deps);
    expect(r.status).toBe(404);
    expect((await db.doc("users/nobody").get()).exists).toBe(false);
  });

  it("an anonymous RevenueCat id is ignored with 200", async () => {
    const r = await handleRevenueCat({ event: { type: "RENEWAL", app_user_id: "$RCAnonymousID:abc" } }, deps);
    expect(r.status).toBe(200);
  });

  it("an event for another entitlement changes nothing", async () => {
    await handleRevenueCat(ev("INITIAL_PURCHASE", { entitlement_ids: ["other"] }), deps);
    expect((await db.doc("users/u1").get()).data()?.plan).toBe("free");
  });

  it("a malformed body is 400", async () => {
    expect((await handleRevenueCat({ nope: 1 }, deps)).status).toBe(400);
  });
});

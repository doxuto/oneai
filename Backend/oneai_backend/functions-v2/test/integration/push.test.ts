/** Runs under `npm run test:integration`. */
import { Timestamp } from "firebase-admin/firestore";
import { beforeEach, describe, expect, it } from "vitest";
import { unitDeps, type Deps } from "../../src/lib/deps.js";
import type { PushMessage, PushSendResult } from "../../src/lib/push/types.js";
import { deviceIdOf } from "../../src/push/_shared.js";
import { registerDeviceHandler, unregisterDeviceHandler, updateNotificationPrefsHandler } from "../../src/push/handler.js";
import { notifyMinuteResult } from "../../src/push/notify.js";
import { getMeHandler } from "../../src/users/handler.js";
import { clearFirestore, fixedNow, testDb } from "../helpers/emulator.js";

const db = testDb();
const client = { appVersion: "2.0.0", build: 1, platform: "ios" as const };
const u1 = { uid: "u1", signInProvider: "google.com" };
const u2 = { uid: "u2", signInProvider: "apple.com" };
const TOKEN = "fcm-token-".padEnd(60, "a");
const TOKEN2 = "fcm-token-".padEnd(60, "b");

function recorder(outcome: (m: PushMessage) => Partial<PushSendResult> = () => ({})) {
  const sent: PushMessage[] = [];
  return {
    sent,
    push: { send: async (ms: PushMessage[]) => { sent.push(...ms); return ms.map((m) => ({ token: m.token, ok: true, unregistered: false, ...outcome(m) })); } },
  };
}
const makeDeps = (push: Deps["services"]["push"]): Deps => unitDeps({ db, now: fixedNow(), services: { push } });

describe("registerDevice / unregisterDevice", () => {
  beforeEach(() => clearFirestore());

  it("upserts under the caller with platform, locale and app version; re-registering keeps createdAt", async () => {
    const deps = makeDeps(recorder().push);
    await registerDeviceHandler(u1, { client, token: TOKEN, locale: "vi-VN" }, deps);
    const first = (await db.doc(`users/u1/devices/${deviceIdOf(TOKEN)}`).get()).data();
    expect(first).toMatchObject({ token: TOKEN, platform: "ios", locale: "vi-VN", appVersion: "2.0.0" });
    expect(first?.createdAt).toBeInstanceOf(Timestamp);

    await registerDeviceHandler(u1, { client: { ...client, appVersion: "2.1.0" }, token: TOKEN, locale: "en-US" }, deps);
    const again = (await db.doc(`users/u1/devices/${deviceIdOf(TOKEN)}`).get()).data();
    expect(again).toMatchObject({ locale: "en-US", appVersion: "2.1.0" });
    expect(again?.createdAt.isEqual(first?.createdAt)).toBe(true);
    expect((await db.collection("users/u1/devices").get()).size).toBe(1);
  });

  it("a token moves to whoever signs in on that phone — the previous account stops receiving it", async () => {
    const deps = makeDeps(recorder().push);
    await registerDeviceHandler(u1, { client, token: TOKEN }, deps);
    await registerDeviceHandler(u2, { client, token: TOKEN }, deps);
    expect((await db.collection("users/u1/devices").get()).size).toBe(0);
    expect((await db.collection("users/u2/devices").get()).size).toBe(1);
  });

  it("unregister is idempotent and only touches the caller", async () => {
    const deps = makeDeps(recorder().push);
    await registerDeviceHandler(u1, { client, token: TOKEN }, deps);
    await registerDeviceHandler(u2, { client, token: TOKEN2 }, deps);
    await unregisterDeviceHandler(u1, { client, token: TOKEN }, deps);
    await unregisterDeviceHandler(u1, { client, token: TOKEN }, deps);
    await unregisterDeviceHandler(u1, { client, token: TOKEN2 }, deps); // not theirs → no-op
    expect((await db.collection("users/u1/devices").get()).size).toBe(0);
    expect((await db.collection("users/u2/devices").get()).size).toBe(1);
  });
});

describe("notification prefs", () => {
  beforeEach(() => clearFirestore());

  it("round-trips through getMe and defaults to on", async () => {
    const deps = makeDeps(recorder().push);
    await db.doc("users/u1").set({ plan: "free", createdAt: Timestamp.now() });
    expect((await getMeHandler(u1, { client }, deps)).user.notifications).toEqual({ transcriptionDone: true });
    const out = await updateNotificationPrefsHandler(u1, { client, transcriptionDone: false }, deps);
    expect(out.notifications).toEqual({ transcriptionDone: false });
    expect((await getMeHandler(u1, { client }, deps)).user.notifications).toEqual({ transcriptionDone: false });
    expect((await db.doc("users/u1").get()).data()?.plan).toBe("free"); // merge, not overwrite
  });
});

describe("notifyMinuteResult", () => {
  beforeEach(() => clearFirestore());

  it("sends one localised message per device, collapsed per note, with routing data", async () => {
    const r = recorder();
    const deps = makeDeps(r.push);
    await db.doc("users/u1").set({ plan: "free" });
    await registerDeviceHandler(u1, { client, token: TOKEN, locale: "vi" }, deps);
    await registerDeviceHandler(u1, { client: { ...client, platform: "android" }, token: TOKEN2, locale: "en-GB" }, deps);

    const report = await notifyMinuteResult(deps, "u1", { minuteId: "m1", title: "Standup", kind: "minuteReady" });
    expect(report).toEqual({ sent: 2, pruned: 0, skipped: null });
    expect(r.sent).toHaveLength(2);
    const byToken = Object.fromEntries(r.sent.map((m) => [m.token, m]));
    expect(byToken[TOKEN]).toMatchObject({ title: "Ghi chú đã sẵn sàng", data: { type: "minuteReady", minuteId: "m1" }, collapseKey: "minute:m1" });
    expect(byToken[TOKEN2]?.title).toBe("Your note is ready");
    expect(byToken[TOKEN2]?.body).toContain('"Standup"');
  });

  it("respects the user's preference and the absence of devices without calling FCM", async () => {
    const r = recorder();
    const deps = makeDeps(r.push);
    await db.doc("users/u1").set({ notifications: { transcriptionDone: false } });
    await registerDeviceHandler(u1, { client, token: TOKEN }, deps);
    expect(await notifyMinuteResult(deps, "u1", { minuteId: "m1", title: "t", kind: "minuteReady" })).toMatchObject({ skipped: "prefs" });
    await db.doc("users/u2").set({});
    expect(await notifyMinuteResult(deps, "u2", { minuteId: "m1", title: "t", kind: "minuteReady" })).toMatchObject({ skipped: "noDevices" });
    expect(r.sent).toHaveLength(0);
  });

  it("prunes tokens FCM reports as dead and keeps the rest", async () => {
    const r = recorder((m) => (m.token === TOKEN ? { ok: false, unregistered: true, error: "messaging/registration-token-not-registered" } : {}));
    const deps = makeDeps(r.push);
    await db.doc("users/u1").set({});
    await registerDeviceHandler(u1, { client, token: TOKEN }, deps);
    await registerDeviceHandler(u1, { client, token: TOKEN2 }, deps);
    expect(await notifyMinuteResult(deps, "u1", { minuteId: "m1", title: "t", kind: "minuteFailed" })).toEqual({ sent: 1, pruned: 1, skipped: null });
    const left = (await db.collection("users/u1/devices").get()).docs.map((d) => d.data().token);
    expect(left).toEqual([TOKEN2]);
  });

  it("a push outage is logged, never thrown", async () => {
    const deps = makeDeps({ send: async () => { throw new Error("fcm down"); } });
    await db.doc("users/u1").set({});
    await registerDeviceHandler(u1, { client, token: TOKEN }, deps);
    await expect(notifyMinuteResult(deps, "u1", { minuteId: "m1", title: "t", kind: "minuteReady" })).resolves.toEqual({ sent: 0, pruned: 0, skipped: null });
  });
});

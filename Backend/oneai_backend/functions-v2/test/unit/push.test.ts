import { describe, expect, it } from "vitest";
import { classify, toFcmMessage } from "../../src/lib/push/fcm.js";
import { unitDeps } from "../../src/lib/deps.js";
import { deviceIdOf, toPrefs } from "../../src/push/_shared.js";
import { notificationCopy, pickLocale } from "../../src/push/copy.js";
import { registerDeviceHandler, updateNotificationPrefsHandler } from "../../src/push/handler.js";
import { toUserOutput } from "../../src/users/_shared.js";

const client = { appVersion: "2.0.0", build: 1, platform: "ios" as const };
const caller = { uid: "u1", signInProvider: "google.com" };

describe("copy", () => {
  it("picks the language from any locale spelling, defaulting to English", () => {
    expect(pickLocale("vi-VN")).toBe("vi");
    expect(pickLocale("es_419")).toBe("es");
    expect(pickLocale("EN")).toBe("en");
    expect(pickLocale("pt-BR")).toBe("en");
    expect(pickLocale(null)).toBe("en");
  });
  it("puts the note title in the body, truncated, and never an empty title", () => {
    expect(notificationCopy("minuteReady", "vi", "Họp sáng")).toEqual({ title: "Ghi chú đã sẵn sàng", body: '"Họp sáng" đã được chuyển thành văn bản và tóm tắt.' });
    expect(notificationCopy("minuteFailed", "en", "   ").body).toContain('"Untitled"');
    const long = "x".repeat(100);
    expect(notificationCopy("minuteReady", "es", long).body).toContain(`"${"x".repeat(59)}…"`);
  });
});

describe("fcm mapping", () => {
  it("dead-token codes are flagged for pruning; other failures are not", () => {
    expect(classify("t", { success: true })).toEqual({ token: "t", ok: true, unregistered: false });
    expect(classify("t", { success: false, error: { code: "messaging/registration-token-not-registered" } })).toMatchObject({ ok: false, unregistered: true });
    expect(classify("t", { success: false, error: { code: "messaging/internal-error" } })).toMatchObject({ ok: false, unregistered: false, error: "messaging/internal-error" });
  });
  it("builds a high-priority, collapsible message for both platforms", () => {
    const m = toFcmMessage({ token: "t", title: "T", body: "B", data: { type: "minuteReady", minuteId: "m1" }, collapseKey: "minute:m1" });
    expect(m).toMatchObject({ token: "t", notification: { title: "T", body: "B" }, data: { type: "minuteReady", minuteId: "m1" } });
    expect((m as { android: { priority: string; collapseKey: string } }).android).toMatchObject({ priority: "high", collapseKey: "minute:m1" });
    expect((m as { apns: { headers: Record<string, string> } }).apns.headers["apns-collapse-id"]).toBe("minute:m1");
  });
});

describe("prefs + device ids", () => {
  it("prefs default to on and tolerate junk", () => {
    expect(toPrefs(undefined)).toEqual({ transcriptionDone: true });
    expect(toPrefs({ transcriptionDone: "no" })).toEqual({ transcriptionDone: true });
    expect(toPrefs({ transcriptionDone: false })).toEqual({ transcriptionDone: false });
    expect(toUserOutput("u1", {}, new Date()).notifications).toEqual({ transcriptionDone: true });
  });
  it("device id is a stable hash, safe as a doc id for any token", () => {
    const t = "a:b/c".repeat(200);
    expect(deviceIdOf(t)).toBe(deviceIdOf(t));
    expect(deviceIdOf(t)).toMatch(/^[0-9a-f]{40}$/);
    expect(deviceIdOf(t)).not.toBe(deviceIdOf(`${t}x`));
  });
});

describe("validation (never reaches Firestore)", () => {
  const deps = unitDeps();
  it("registerDevice needs a plausible token and no extra keys", async () => {
    await expect(registerDeviceHandler(caller, { client, token: "short" }, deps)).rejects.toMatchObject({ code: "invalid-argument" });
    await expect(registerDeviceHandler(caller, { client, token: "x".repeat(40), uid: "someone-else" }, deps)).rejects.toMatchObject({ code: "invalid-argument" });
    await expect(registerDeviceHandler(undefined, { client, token: "x".repeat(40) }, deps)).rejects.toMatchObject({ code: "unauthenticated" });
  });
  it("updateNotificationPrefs wants a boolean", async () => {
    await expect(updateNotificationPrefsHandler(caller, { client, transcriptionDone: "yes" }, deps)).rejects.toMatchObject({ code: "invalid-argument" });
  });
});

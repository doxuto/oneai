import { Timestamp } from "firebase-admin/firestore";
import { describe, expect, it } from "vitest";
import { unitDeps } from "../../src/lib/deps.js";
import { effectivePlan, toUserOutput } from "../../src/users/_shared.js";
import { getMeHandler } from "../../src/users/handler.js";

const client = { appVersion: "2.0.0", build: 1, platform: "ios" as const };
const caller = { uid: "u1", signInProvider: "google.com" };

describe("getMeHandler — branches that never reach Firestore", () => {
  it("rejects an unauthenticated caller before touching db", async () => {
    await expect(getMeHandler(undefined, { client }, unitDeps())).rejects.toMatchObject({
      code: "unauthenticated",
    });
  });

  it("rejects an anonymous session with reason:anonymous", async () => {
    await expect(
      getMeHandler({ uid: "u1", signInProvider: "anonymous" }, { client }, unitDeps()),
    ).rejects.toMatchObject({ code: "permission-denied", details: { reason: "anonymous" } });
  });

  it("rejects a missing client block with issues[]", async () => {
    const err = await getMeHandler(caller, {}, unitDeps()).catch((e: unknown) => e);
    expect(err).toMatchObject({ code: "invalid-argument" });
    expect((err as { details: { issues: unknown[] } }).details.issues.length).toBeGreaterThan(0);
  });

  it("gates on min client version with details.minVersion", async () => {
    await expect(
      getMeHandler(caller, { client: { ...client, appVersion: "1.9.0" } }, unitDeps()),
    ).rejects.toMatchObject({ code: "failed-precondition", details: { minVersion: "2.0.0" } });
  });
});

describe("effectivePlan", () => {
  const now = new Date("2026-09-23T00:00:00Z");
  it("free when plan is missing", () => expect(effectivePlan({}, now)).toBe("free"));
  it("premium with no expiry stays premium", () =>
    expect(effectivePlan({ plan: "premium", planExpiresAt: null }, now)).toBe("premium"));
  it("premium past expiry is free — a missed webhook cannot grant premium forever", () =>
    expect(
      effectivePlan(
        { plan: "premium", planExpiresAt: Timestamp.fromDate(new Date("2026-09-01T00:00:00Z")) },
        now,
      ),
    ).toBe("free"));
  it("premium before expiry is premium", () =>
    expect(
      effectivePlan(
        { plan: "premium", planExpiresAt: Timestamp.fromDate(new Date("2026-12-01T00:00:00Z")) },
        now,
      ),
    ).toBe("premium"));
});

describe("toUserOutput", () => {
  it("maps an empty doc to nulls and zeros, never undefined", () => {
    const out = toUserOutput("u1", undefined, new Date());
    expect(out).toEqual({
      id: "u1",
      email: null,
      displayName: null,
      photoUrl: null,
      plan: "free",
      planExpiresAt: null,
      minuteCount: 0,
      createdAt: null,
      notifications: { transcriptionDone: true },
    });
  });

  it("turns Timestamp into ISO-8601, never {_seconds,_nanoseconds}", () => {
    const out = toUserOutput(
      "u1",
      { createdAt: Timestamp.fromDate(new Date("2026-09-22T08:41:12.345Z")) },
      new Date(),
    );
    expect(out.createdAt).toBe("2026-09-22T08:41:12.345Z");
  });

  it("ignores a non-string email rather than crashing", () => {
    expect(toUserOutput("u1", { email: 42 }, new Date()).email).toBeNull();
  });
});

describe("deleteAccountHandler", () => {
  it("requires confirm:true, literally", async () => {
    const { deleteAccountHandler } = await import("../../src/users/deleteAccount.js");
    await expect(deleteAccountHandler(caller, { client, confirm: false }, unitDeps(), async () => undefined)).rejects.toMatchObject({ code: "invalid-argument" });
    await expect(deleteAccountHandler(caller, { client }, unitDeps(), async () => undefined)).rejects.toMatchObject({ code: "invalid-argument" });
  });
  it("unauthenticated first", async () => {
    const { deleteAccountHandler } = await import("../../src/users/deleteAccount.js");
    await expect(deleteAccountHandler(undefined, { client, confirm: true }, unitDeps(), async () => undefined)).rejects.toMatchObject({ code: "unauthenticated" });
  });
});

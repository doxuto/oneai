import { describe, expect, it } from "vitest";
import { unitDeps } from "../../src/lib/deps.js";
import { nameKey, toTagOutput } from "../../src/tags/_shared.js";
import { createTagHandler, deleteTagHandler, updateTagHandler } from "../../src/tags/handler.js";

const client = { appVersion: "2.0.0", build: 1, platform: "android" as const };
const caller = { uid: "u1", signInProvider: "google.com" };
const deps = unitDeps();

describe("nameKey", () => {
  it("is case-insensitive", () => expect(nameKey("Work")).toBe(nameKey("WORK")));
  it("collapses whitespace", () => expect(nameKey("  team   sync ")).toBe("team sync"));
  it("distinguishes genuinely different names", () => expect(nameKey("work")).not.toBe(nameKey("works")));
});

describe("validation", () => {
  it("createTag: empty after trim is invalid-argument", async () => {
    await expect(createTagHandler(caller, { client, name: "   " }, deps)).rejects.toMatchObject({
      code: "invalid-argument",
    });
  });
  it("createTag: over 40 chars is invalid-argument", async () => {
    await expect(createTagHandler(caller, { client, name: "x".repeat(41) }, deps)).rejects.toMatchObject({
      code: "invalid-argument",
    });
  });
  it("updateTag: extra keys rejected", async () => {
    await expect(
      updateTagHandler(caller, { client, tagId: "t1", name: "a", minuteCount: 999 }, deps),
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });
  it("deleteTag: unauthenticated", async () => {
    await expect(deleteTagHandler(undefined, { client, tagId: "t1" }, deps)).rejects.toMatchObject({
      code: "unauthenticated",
    });
  });
});

describe("toTagOutput", () => {
  it("defaults", () => {
    expect(toTagOutput("t1", undefined)).toEqual({
      id: "t1",
      name: "",
      minuteCount: 0,
      createdAt: "1970-01-01T00:00:00.000Z",
    });
  });
});

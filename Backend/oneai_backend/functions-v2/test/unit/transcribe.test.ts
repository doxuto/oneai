import { describe, expect, it } from "vitest";
import { unitDeps } from "../../src/lib/deps.js";
import { cancelTranscriptionHandler, startTranscriptionHandler } from "../../src/transcribe/handler.js";
import { StartTranscriptionInput, TaskPayload } from "../../src/transcribe/types.js";

const client = { appVersion: "2.0.0", build: 1, platform: "ios" as const };
const caller = { uid: "u1", signInProvider: "google.com" };
const deps = unitDeps();
const base = { client, minuteId: "m1", requestId: "3f2f1b9e-7a4a-4c1e-9d3a-2b7f0c9a1d11", summaryLanguage: "vi", timezone: "Asia/Ho_Chi_Minh" };

describe("StartTranscriptionInput", () => {
  it("defaults audioLanguage to auto and keywords to []", () => {
    const p = StartTranscriptionInput.parse(base);
    expect(p.audioLanguage).toBe("auto");
    expect(p.keywords).toEqual([]);
  });
  it("requires a UUID requestId", () => {
    expect(() => StartTranscriptionInput.parse({ ...base, requestId: "nope" })).toThrow();
  });
  it("timezone must be IANA, not 'GMT -7' as v1 defaulted to", () => {
    expect(() => StartTranscriptionInput.parse({ ...base, timezone: "GMT -7" })).toThrow();
    expect(StartTranscriptionInput.parse({ ...base, timezone: "Europe/Paris" }).timezone).toBe("Europe/Paris");
  });
  it("keywords is an array, capped at 20 (v1 stored a comma string here)", () => {
    expect(() => StartTranscriptionInput.parse({ ...base, keywords: "a,b" })).toThrow();
    expect(() => StartTranscriptionInput.parse({ ...base, keywords: Array(21).fill("k") })).toThrow();
  });
  it("template defaults to auto and only accepts the known set (S11-08)", () => {
    expect(StartTranscriptionInput.parse(base).template).toBe("auto");
    expect(StartTranscriptionInput.parse({ ...base, template: "standup" }).template).toBe("standup");
    expect(() => StartTranscriptionInput.parse({ ...base, template: "retro" })).toThrow();
  });

  it("rejects unknown keys", () => {
    expect(() => StartTranscriptionInput.parse({ ...base, uid: "u2" })).toThrow();
  });
});

describe("handlers — branches before Firestore", () => {
  it("start: unauthenticated", async () => {
    await expect(startTranscriptionHandler(undefined, base, deps)).rejects.toMatchObject({ code: "unauthenticated" });
  });
  it("start: invalid input never touches db", async () => {
    await expect(startTranscriptionHandler(caller, { ...base, requestId: "x" }, deps)).rejects.toMatchObject({ code: "invalid-argument" });
  });
  it("cancel: unauthenticated", async () => {
    await expect(cancelTranscriptionHandler(undefined, { client, minuteId: "m1" }, deps)).rejects.toMatchObject({ code: "unauthenticated" });
  });
});

describe("TaskPayload", () => {
  it("rejects ids with slashes", () => {
    expect(TaskPayload.safeParse({ uid: "u/1", minuteId: "m", jobId: "j" }).success).toBe(false);
    expect(TaskPayload.safeParse({ uid: "u1", minuteId: "m", jobId: "j" }).success).toBe(true);
  });
});

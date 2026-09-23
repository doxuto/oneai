import { Timestamp } from "firebase-admin/firestore";
import { describe, expect, it } from "vitest";
import { unitDeps } from "../../src/lib/deps.js";
import { sourceExpiryFor } from "../../src/jobs/retention.js";
import {
  contentTypeMatches,
  safeFileName,
  toMinuteDetail,
  toCalendarEvents,
  presentArtifactKinds,
  toMinuteSummary,
  toSpeakers,
  toSummary,
  toTranscript,
} from "../../src/minutes/_shared.js";
import { ListMinutesInput } from "../../src/minutes/types.js";
import {
  createMinuteHandler,
  deleteMinuteHandler,
  getMinuteHandler,
  listMinutesHandler,
  updateMinuteHandler,
} from "../../src/minutes/handler.js";

const client = { appVersion: "2.0.0", build: 1, platform: "ios" as const };
const caller = { uid: "u1", signInProvider: "google.com" };
const deps = unitDeps();

describe("input validation (never reaches Firestore)", () => {
  it("createMinute: sizeBytes above 300MB is invalid-argument", async () => {
    await expect(
      createMinuteHandler(
        caller,
        { client, sourceType: "audio", fileName: "a.m4a", sizeBytes: 301 * 1024 * 1024, contentType: "audio/m4a" },
        deps,
      ),
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  it("createMinute: pdf declared but audio content type is invalid-argument on contentType", async () => {
    await expect(
      createMinuteHandler(
        caller,
        { client, sourceType: "pdf", fileName: "a.pdf", sizeBytes: 10, contentType: "audio/mpeg" },
        deps,
      ),
    ).rejects.toMatchObject({ code: "invalid-argument", details: { field: "contentType" } });
  });

  it("createMinute: youtube is no longer a source type", async () => {
    await expect(
      createMinuteHandler(
        caller,
        { client, sourceType: "youtube", fileName: "x", sizeBytes: 1, contentType: "audio/mpeg" },
        deps,
      ),
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  it("createMinute: unknown keys are rejected (strict)", async () => {
    await expect(
      createMinuteHandler(
        caller,
        { client, sourceType: "audio", fileName: "a.m4a", sizeBytes: 1, contentType: "audio/m4a", uid: "hacker" },
        deps,
      ),
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  it("listMinutes: limit above 50 is invalid-argument", async () => {
    await expect(listMinutesHandler(caller, { client, limit: 51 }, deps)).rejects.toMatchObject({
      code: "invalid-argument",
    });
  });

  it("listMinutes: more than 10 tagIds is invalid-argument", async () => {
    const tagIds = Array.from({ length: 11 }, (_, i) => `t${i}`);
    await expect(listMinutesHandler(caller, { client, tagIds }, deps)).rejects.toMatchObject({
      code: "invalid-argument",
    });
  });

  it("listMinutes: `page` is stripped, never honoured (cursor-only pagination)", () => {
    const parsed = ListMinutesInput.parse({ client, page: 2 });
    expect(parsed).not.toHaveProperty("page");
    expect(parsed.limit).toBe(20);
    expect(parsed.sort).toBe("createdAtDesc");
  });

  it("getMinute: an id containing '/' is invalid-argument", async () => {
    await expect(getMinuteHandler(caller, { client, minuteId: "a/b" }, deps)).rejects.toMatchObject({
      code: "invalid-argument",
    });
  });

  it("updateMinute: no fields at all is invalid-argument", async () => {
    await expect(updateMinuteHandler(caller, { client, minuteId: "m1" }, deps)).rejects.toMatchObject({
      code: "invalid-argument",
    });
  });

  it("updateMinute: summaryText and transcription cannot be written by the client any more", async () => {
    await expect(
      updateMinuteHandler(caller, { client, minuteId: "m1", title: "x", summaryText: "pwn" }, deps),
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  it("deleteMinute: unauthenticated first", async () => {
    await expect(deleteMinuteHandler(undefined, { client, minuteId: "m1" }, deps)).rejects.toMatchObject({
      code: "unauthenticated",
    });
  });
});

describe("safeFileName", () => {
  it("keeps only the basename", () => expect(safeFileName("../../etc/passwd")).toBe("passwd"));
  it("strips path separators of both kinds", () => expect(safeFileName("a\\b/c.m4a")).toBe("c.m4a"));
  it("drops leading dots", () => expect(safeFileName(".hidden.mp3")).toBe("hidden.mp3"));
  it("replaces non-ASCII with underscores", () => expect(safeFileName("họp 22-09.m4a")).toBe("h_p 22-09.m4a"));
  it("never returns empty", () => expect(safeFileName("///")).toBe("file"));
  it("caps length", () => expect(safeFileName("a".repeat(500) + ".m4a").length).toBeLessThanOrEqual(120));
});

describe("contentTypeMatches", () => {
  it("audio/* for audio", () => expect(contentTypeMatches("audio", "audio/x-m4a")).toBe(true));
  it("iOS voice memos come as video/mp4 sometimes", () => expect(contentTypeMatches("audio", "video/mp4")).toBe(true));
  it("pdf needs application/pdf", () => {
    expect(contentTypeMatches("pdf", "application/pdf")).toBe(true);
    expect(contentTypeMatches("pdf", "audio/mpeg")).toBe(false);
  });
  it("is case-insensitive", () => expect(contentTypeMatches("pdf", "Application/PDF")).toBe(true));
});

describe("mappers", () => {
  it("toMinuteSummary on an empty doc gives safe defaults, never undefined", () => {
    expect(toMinuteSummary("m1", undefined)).toEqual({
      id: "m1",
      title: "Untitled",
      iconEmoji: null,
      sourceType: "audio",
      contentKind: null,
      status: "failed",
      durationSeconds: null,
      tagIds: [],
      createdAt: "1970-01-01T00:00:00.000Z",
      updatedAt: "1970-01-01T00:00:00.000Z",
    });
  });

  it("toMinuteSummary converts Timestamp to ISO and filters non-string tagIds", () => {
    const s = toMinuteSummary("m1", {
      title: "Standup",
      status: "ready",
      tagIds: ["t1", 3, null, "t2"],
      createdAt: Timestamp.fromDate(new Date("2026-09-22T01:02:03.004Z")),
    });
    expect(s.createdAt).toBe("2026-09-22T01:02:03.004Z");
    expect(s.updatedAt).toBe("2026-09-22T01:02:03.004Z"); // falls back to createdAt
    expect(s.tagIds).toEqual(["t1", "t2"]);
    expect(s.status).toBe("ready");
  });

  it("toMinuteSummary maps an unknown status to failed rather than leaking a raw string", () => {
    expect(toMinuteSummary("m1", { status: "IN_PROGRESS" }).status).toBe("failed");
  });

  it("toSummary tolerates junk sections", () => {
    expect(toSummary({ title: "T", text: "x", sections: [null, 1, { title: "a", bullets: ["b", 2] }] })).toEqual({
      title: "T",
      text: "x",
      icon: null,
      sections: [{ title: "a", bullets: ["b"] }],
    });
  });

  it("toTranscript uses numeric seconds, not v1's 'MM:SS - MM:SS' strings", () => {
    const t = toTranscript({
      durationSeconds: 90.5,
      text: "hello",
      segments: [{ startSeconds: 0, endSeconds: 4.2, text: "hello", speakerId: "speaker_0", speakerLabel: "Speaker 1" }],
    });
    expect(t?.segments[0]?.endSeconds).toBe(4.2);
    expect(t?.durationSeconds).toBe(90.5);
  });

  it("toSpeakers drops entries without an id", () => {
    expect(toSpeakers({ speakers: [{ id: "speaker_0", label: "Ana" }, { label: "no id" }] })).toEqual([
      { id: "speaker_0", label: "Ana" },
    ]);
  });

  it("toMinuteDetail carries failure as {code,message} or null", () => {
    const d = toMinuteDetail("m1", { status: "failed", failure: { code: "stt_timeout", message: "took too long" } }, {
      transcript: null,
      speakers: [],
    });
    expect(d.failure).toEqual({ code: "stt_timeout", message: "took too long" });
    expect(toMinuteDetail("m1", {}, { transcript: null, speakers: [] }).failure).toBeNull();
  });

  it("sourceState is derived: none / available / expired", () => {
    expect(toMinuteDetail("m1", {}, { transcript: null, speakers: [] }).sourceState).toBe("none");
    expect(toMinuteDetail("m1", { sourcePath: "p" }, { transcript: null, speakers: [] }).sourceState).toBe("available");
    expect(toMinuteDetail("m1", { sourcePath: null, sourceState: "expired" }, { transcript: null, speakers: [] })).toMatchObject({ sourceState: "expired", sourcePath: null, sourceExpiresAt: null });
  });

  it("sourceExpiryFor: by days, -1 = never", () => {
    const t = new Date("2026-09-23T00:00:00Z");
    expect(sourceExpiryFor(t, 7)?.toISOString()).toBe("2026-09-30T00:00:00.000Z");
    expect(sourceExpiryFor(t, 0)?.toISOString()).toBe(t.toISOString());
    expect(sourceExpiryFor(t, -1)).toBeNull();
  });

  it("toMinuteDetail defaults calendarEvents and availableArtifacts to empty", () => {
    const d = toMinuteDetail("m1", {}, { transcript: null, speakers: [] });
    expect(d.calendarEvents).toEqual([]);
    expect(d.availableArtifacts).toEqual([]);
  });

  it("toCalendarEvents tolerates junk and drops empty events; presentArtifactKinds keeps canonical order", () => {
    expect(toCalendarEvents(undefined)).toEqual([]);
    expect(toCalendarEvents({ events: "nope" })).toEqual([]);
    expect(toCalendarEvents({ events: [null, 7, { title: "", datetime: "" }, { id: "e1", title: "Retro", datetime: "2026-09-25", participants: ["Ana", 3] }] })).toEqual([
      { id: "e1", title: "Retro", description: "", datetime: "2026-09-25", participants: ["Ana"], rawText: "" },
    ]);
    expect(presentArtifactKinds(["calendarEvents", "junk", "quiz", "speakers"])).toEqual(["quiz", "speakers", "calendarEvents"]);
  });
});

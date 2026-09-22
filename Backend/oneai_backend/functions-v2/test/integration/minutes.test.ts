/** Runs under `npm run test:integration` (firebase emulators:exec). */
import { getStorage } from "firebase-admin/storage";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { beforeEach, describe, expect, it } from "vitest";
import { unitDeps, type Deps } from "../../src/lib/deps.js";
import {
  createMinuteHandler,
  deleteMinuteHandler,
  getMinuteHandler,
  listMinutesHandler,
  updateMinuteHandler,
} from "../../src/minutes/handler.js";
import { clearFirestore, fixedNow, testDb } from "../helpers/emulator.js";

const db = testDb();
const bucket = getStorage().bucket("demo-oneai.appspot.com");
const deps: Deps = unitDeps({ db, bucket: bucket as Deps["bucket"], now: fixedNow() });
const client = { appVersion: "2.0.0", build: 1, platform: "ios" as const };
const u1 = { uid: "u1", signInProvider: "google.com" };
const u2 = { uid: "u2", signInProvider: "apple.com" };

async function seedMinute(uid: string, id: string, data: Record<string, unknown>) {
  await db.doc(`users/${uid}/minutes/${id}`).set({
    title: id,
    status: "ready",
    sourceType: "audio",
    tagIds: [],
    createdAt: Timestamp.fromDate(new Date("2026-09-01T00:00:00Z")),
    updatedAt: Timestamp.fromDate(new Date("2026-09-01T00:00:00Z")),
    ...data,
  });
}

describe("createMinute", () => {
  beforeEach(() => clearFirestore());

  it("creates an uploading doc under the caller and returns the storage path", async () => {
    const out = await createMinuteHandler(
      u1,
      { client, sourceType: "audio", fileName: "Standup 22-09.m4a", sizeBytes: 1234, contentType: "audio/x-m4a" },
      deps,
    );
    expect(out.upload.path).toBe(`users/u1/minutes/${out.minuteId}/source/Standup 22-09.m4a`);
    expect(out.upload.maxSizeBytes).toBe(300 * 1024 * 1024);

    const snap = await db.doc(`users/u1/minutes/${out.minuteId}`).get();
    expect(snap.exists).toBe(true);
    expect(snap.data()).toMatchObject({
      status: "uploading",
      sourceType: "audio",
      title: "Standup 22-09",
      sourceSizeBytes: 1234,
      tagIds: [],
    });
    expect(snap.data()?.createdAt).toBeInstanceOf(Timestamp);
  });

  it("neutralises a path-traversal file name", async () => {
    const out = await createMinuteHandler(
      u1,
      { client, sourceType: "pdf", fileName: "../../../etc/passwd.pdf", sizeBytes: 10, contentType: "application/pdf" },
      deps,
    );
    expect(out.upload.path).toBe(`users/u1/minutes/${out.minuteId}/source/passwd.pdf`);
  });
});

describe("listMinutes", () => {
  beforeEach(async () => {
    await clearFirestore();
    for (let i = 0; i < 7; i++) {
      await seedMinute("u1", `m${i}`, {
        title: `Title ${String.fromCharCode(97 + i)}`,
        tagIds: i % 2 === 0 ? ["even"] : ["odd"],
        createdAt: Timestamp.fromDate(new Date(`2026-09-0${i + 1}T00:00:00Z`)),
      });
    }
    await seedMinute("u2", "other", {});
  });

  it("pages newest-first with an opaque cursor and no overlap or gap", async () => {
    const p1 = await listMinutesHandler(u1, { client, limit: 3 }, deps);
    expect(p1.items.map((m) => m.id)).toEqual(["m6", "m5", "m4"]);
    expect(p1.nextCursor).not.toBeNull();

    const p2 = await listMinutesHandler(u1, { client, limit: 3, cursor: p1.nextCursor! }, deps);
    expect(p2.items.map((m) => m.id)).toEqual(["m3", "m2", "m1"]);

    const p3 = await listMinutesHandler(u1, { client, limit: 3, cursor: p2.nextCursor! }, deps);
    expect(p3.items.map((m) => m.id)).toEqual(["m0"]);
    expect(p3.nextCursor).toBeNull();
  });

  it("never returns another user's notes", async () => {
    const all = await listMinutesHandler(u1, { client, limit: 50 }, deps);
    expect(all.items.some((m) => m.id === "other")).toBe(false);
  });

  it("filters by tag", async () => {
    const evens = await listMinutesHandler(u1, { client, tagIds: ["even"] }, deps);
    expect(evens.items.map((m) => m.id).sort()).toEqual(["m0", "m2", "m4", "m6"]);
  });

  it("sorts by title when asked", async () => {
    const byTitle = await listMinutesHandler(u1, { client, sort: "titleAsc", limit: 2 }, deps);
    expect(byTitle.items.map((m) => m.title)).toEqual(["Title a", "Title b"]);
    const next = await listMinutesHandler(u1, { client, sort: "titleAsc", limit: 2, cursor: byTitle.nextCursor! }, deps);
    expect(next.items.map((m) => m.title)).toEqual(["Title c", "Title d"]);
  });

  it("rejects a cursor from the other sort order", async () => {
    const byDate = await listMinutesHandler(u1, { client, limit: 1 }, deps);
    await expect(
      listMinutesHandler(u1, { client, sort: "titleAsc", cursor: byDate.nextCursor! }, deps),
    ).rejects.toMatchObject({ code: "invalid-argument" });
  });

  it("rejects a tampered cursor", async () => {
    await expect(listMinutesHandler(u1, { client, cursor: "bm90LWpzb24" }, deps)).rejects.toMatchObject({
      code: "invalid-argument",
    });
  });
});

describe("getMinute", () => {
  beforeEach(() => clearFirestore());

  it("returns the detail with speakers artifact and transcript from Storage", async () => {
    const transcript = {
      durationSeconds: 12.5,
      languageCode: "eng",
      languageProbability: 0.98,
      text: "hello world",
      segments: [{ startSeconds: 0, endSeconds: 12.5, text: "hello world", speakerId: "speaker_0", speakerLabel: "Speaker 1" }],
    };
    await bucket.file("users/u1/minutes/m1/transcript.json").save(JSON.stringify(transcript), {
      contentType: "application/json",
    });
    await seedMinute("u1", "m1", {
      summary: { title: "Sum", text: "body", icon: "📝", sections: [{ title: "A", bullets: ["b1"] }] },
      transcriptPath: "users/u1/minutes/m1/transcript.json",
      sourcePath: "users/u1/minutes/m1/source/a.m4a",
      keywords: ["k1"],
    });
    await db.doc("users/u1/minutes/m1/artifacts/speakers").set({
      kind: "speakers",
      data: { speakers: [{ id: "speaker_0", label: "Ana" }] },
    });

    const { minute } = await getMinuteHandler(u1, { client, minuteId: "m1" }, deps);
    expect(minute.summary?.sections[0]?.bullets).toEqual(["b1"]);
    expect(minute.transcript?.segments[0]?.endSeconds).toBe(12.5);
    expect(minute.speakers).toEqual([{ id: "speaker_0", label: "Ana" }]);
    expect(minute.sourcePath).toBe("users/u1/minutes/m1/source/a.m4a");
    expect(minute.keywords).toEqual(["k1"]);
  });

  it("is not-found for another user's note (existence is not revealed)", async () => {
    await seedMinute("u2", "m1", {});
    await expect(getMinuteHandler(u1, { client, minuteId: "m1" }, deps)).rejects.toMatchObject({
      code: "not-found",
    });
  });

  it("still answers when the transcript file is missing", async () => {
    await seedMinute("u1", "m1", { transcriptPath: "users/u1/minutes/m1/transcript.json" });
    const { minute } = await getMinuteHandler(u1, { client, minuteId: "m1" }, deps);
    expect(minute.transcript).toBeNull();
    expect(minute.status).toBe("ready");
  });
});

describe("updateMinute", () => {
  beforeEach(async () => {
    await clearFirestore();
    await seedMinute("u1", "m1", {});
    await db.doc("users/u1/tags/t1").set({ name: "Work", nameLower: "work" });
  });

  it("updates title, emoji and tags; trims; dedupes; bumps updatedAt", async () => {
    const { minute } = await updateMinuteHandler(
      u1,
      { client, minuteId: "m1", title: "  Weekly  ", iconEmoji: "🗓️", tagIds: ["t1", "t1"] },
      deps,
    );
    expect(minute).toMatchObject({ title: "Weekly", iconEmoji: "🗓️", tagIds: ["t1"] });
    expect(minute.updatedAt > minute.createdAt).toBe(true);
  });

  it("rejects an unknown tag id", async () => {
    await expect(
      updateMinuteHandler(u1, { client, minuteId: "m1", tagIds: ["nope"] }, deps),
    ).rejects.toMatchObject({ code: "invalid-argument", details: { field: "tagIds" } });
  });

  it("can clear the emoji with null", async () => {
    await updateMinuteHandler(u1, { client, minuteId: "m1", iconEmoji: "🎧" }, deps);
    const { minute } = await updateMinuteHandler(u1, { client, minuteId: "m1", iconEmoji: null }, deps);
    expect(minute.iconEmoji).toBeNull();
  });

  it("cannot touch another user's note", async () => {
    await seedMinute("u2", "m9", {});
    await expect(updateMinuteHandler(u1, { client, minuteId: "m9", title: "x" }, deps)).rejects.toMatchObject({
      code: "not-found",
    });
  });
});

describe("deleteMinute", () => {
  beforeEach(async () => {
    await clearFirestore();
    await seedMinute("u1", "m1", {});
    await db.doc("users/u1/minutes/m1/artifacts/speakers").set({ kind: "speakers", data: {} });
    await db.doc("users/u1/minutes/m1/chat/c1").set({ role: "user", text: "hi", createdAt: FieldValue.serverTimestamp() });
    await bucket.file("users/u1/minutes/m1/source/a.m4a").save("audio-bytes");
    await bucket.file("users/u1/minutes/m1/transcript.json").save("{}");
  });

  it("removes the doc, its subcollections and every file under the prefix", async () => {
    await deleteMinuteHandler(u1, { client, minuteId: "m1" }, deps);

    expect((await db.doc("users/u1/minutes/m1").get()).exists).toBe(false);
    expect((await db.doc("users/u1/minutes/m1/artifacts/speakers").get()).exists).toBe(false);
    expect((await db.doc("users/u1/minutes/m1/chat/c1").get()).exists).toBe(false);
    const [files] = await bucket.getFiles({ prefix: "users/u1/minutes/m1/" });
    expect(files).toHaveLength(0);
  });

  it("is not-found the second time (idempotent from the client's view)", async () => {
    await deleteMinuteHandler(u1, { client, minuteId: "m1" }, deps);
    await expect(deleteMinuteHandler(u1, { client, minuteId: "m1" }, deps)).rejects.toMatchObject({
      code: "not-found",
    });
  });

  it("cannot delete another user's note", async () => {
    await expect(deleteMinuteHandler(u2, { client, minuteId: "m1" }, deps)).rejects.toMatchObject({
      code: "not-found",
    });
    expect((await db.doc("users/u1/minutes/m1").get()).exists).toBe(true);
  });
});

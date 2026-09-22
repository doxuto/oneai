/** Runs under `npm run test:integration`. Seeds v1-shaped data, migrates, then reads it back through the v2 handlers. */
import { getStorage } from "firebase-admin/storage";
import { beforeEach, describe, expect, it } from "vitest";
import { generateQuizHandler } from "../../src/ai/handler.js";
import { unitDeps, type Deps } from "../../src/lib/deps.js";
import { getMinuteHandler, listMinutesHandler } from "../../src/minutes/handler.js";
import { listTagsHandler } from "../../src/tags/handler.js";
import { inventory, migrateAll } from "../../src/tools/migrateV1.js";
import { clearFirestore, fixedNow, testDb } from "../helpers/emulator.js";

const db = testDb();
const bucket = getStorage().bucket("demo-oneai.appspot.com");
const deps: Deps = unitDeps({ db, bucket: bucket as Deps["bucket"], now: fixedNow() });
const client = { appVersion: "2.0.0", build: 1, platform: "ios" as const };
const u1 = { uid: "u1", signInProvider: "google.com" };

async function seedV1() {
  await db.doc("users/u1").set({ uid: "u1", email: "a@b.c", displayName: "A", photoURL: "http://p", role: "user", plan: "premium", credit: 1, createdAt: new Date("2026-01-01") });
  await db.doc("tags/u1/tagItems/t1").set({ name: "Work", name_lower: "work" });
  await db.doc("users/u1/minutes/m1").set({
    title: "Standup", minuteId: "m1", gcsUri: "gs://old/user_uploads/u1/m1/audio/a.m4a", iconAsset: "📝", contentType: "team_meeting",
    sourceType: "audio", duration: "00:10", keywords: "KPI, A1", descriptionAudio: "weekly", summaryLanguage: "en", tags: ["t1", "ghost"], createdAt: new Date("2026-02-01"),
  });
  await db.doc("users/u1/minutes/m1/metadata/transcription").set({ duration: "00:10", transcript: "Hello. Sure.", language_code: "eng", sections: [{ timeRange: "00:00 - 00:04", title: "Hello.", speaker: "Speaker 1", speaker_id: "speaker_0" }, { timeRange: "00:05 - 00:10", title: "Sure.", speaker: "Speaker 2", speaker_id: "speaker_1" }] });
  await db.doc("users/u1/minutes/m1/metadata/summary").set({ type: "team_meeting", title: "Standup", summaryText: "We synced.", icon: "📝", sections: [{ title: "Overview", bullets: ["• We synced."] }] });
  await db.doc("users/u1/minutes/m1/metadata/speakers").set({ speaker_0: "Ana", speaker_1: "speaker_1" });
  await db.doc("users/u1/minutes/m1/metadata/quiz").set({ quiz: [{ question: "q", options: ["A", "B"], answer: "A" }] });
  // a note that never got a transcript
  await db.doc("users/u1/minutes/m2").set({ title: "Broken", sourceType: "youtube", createdAt: "2026-03-01T00:00:00Z" });
}

describe("migrateV1", () => {
  beforeEach(async () => { await clearFirestore(); const [f] = await bucket.getFiles({ prefix: "users/" }); await Promise.all(f.map((x) => x.delete())); await seedV1(); });

  it("inventory counts v1 data", async () => {
    expect(await inventory(db)).toEqual({ users: 1, premiumUsers: 1, minutes: 2, minutesWithTranscript: 1, minutesPdf: 0, minutesYoutube: 1, tags: 1 });
  });

  it("dry run writes nothing", async () => {
    const r = await migrateAll(db, bucket, { dryRun: true, force: false });
    expect(r).toMatchObject({ users: 1, minutes: 2, minutesReady: 1, minutesFailed: 1, tags: 1, artifacts: 2, transcriptsWritten: 0 });
    expect((await db.doc("users/u1/minutes/m1").get()).data()?.migratedAt).toBeUndefined();
    expect((await db.doc("users/u1/tags/t1").get()).exists).toBe(false);
  });

  it("apply: v2 handlers read the migrated note, tags and artifacts", async () => {
    const r = await migrateAll(db, bucket, { dryRun: false, force: false });
    expect(r.transcriptsWritten).toBe(1);

    const list = await listMinutesHandler(u1, { client }, deps);
    expect(list.items.map((m) => [m.id, m.status])).toEqual([["m2", "failed"], ["m1", "ready"]]);

    const { minute } = await getMinuteHandler(u1, { client, minuteId: "m1" }, deps);
    expect(minute).toMatchObject({ title: "Standup", iconEmoji: "📝", contentKind: "team_meeting", durationSeconds: 10, tagIds: ["t1"], keywords: ["KPI", "A1"], description: "weekly", sourcePath: "user_uploads/u1/m1/audio/a.m4a" });
    expect(minute.summary?.text).toBe("We synced.");
    expect(minute.transcript?.segments[1]?.startSeconds).toBe(5);
    expect(minute.speakers).toEqual([{ id: "speaker_0", label: "Ana" }, { id: "speaker_1", label: "speaker_1" }]);

    const tags = await listTagsHandler(u1, { client }, deps);
    expect(tags.items).toMatchObject([{ id: "t1", name: "Work", minuteCount: 1 }]);

    // migrated quiz artifact is served from cache — no model call
    const quiz = await generateQuizHandler(u1, { client, minuteId: "m1" }, deps);
    expect(quiz).toEqual({ data: { items: [{ question: "q", options: ["A", "B"], answerIndex: 0 }] }, cached: true });

    const user = (await db.doc("users/u1").get()).data()!;
    expect(user).toMatchObject({ photoUrl: "http://p", plan: "premium", minuteCount: 2 });
    expect((await db.doc("users/u1/minutes/m1/metadata/summary").get()).exists).toBe(true); // v1 docs left in place
  });

  it("is idempotent: a second apply skips already-migrated notes unless --force", async () => {
    await migrateAll(db, bucket, { dryRun: false, force: false });
    const r2 = await migrateAll(db, bucket, { dryRun: false, force: false });
    expect(r2).toMatchObject({ minutes: 0, minutesSkipped: 2 });
    const r3 = await migrateAll(db, bucket, { dryRun: false, force: true });
    expect(r3.minutes).toBe(2);
  });
});

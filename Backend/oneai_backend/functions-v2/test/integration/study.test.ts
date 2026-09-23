/** Runs under `npm run test:integration`. */
import { Timestamp } from "firebase-admin/firestore";
import { beforeEach, describe, expect, it } from "vitest";
import { remindDueReviews } from "../../src/jobs/remindReviews.js";
import { unitDeps, type Deps } from "../../src/lib/deps.js";
import type { PushMessage } from "../../src/lib/push/types.js";
import { deleteMinuteHandler } from "../../src/minutes/handler.js";
import { deviceIdOf } from "../../src/push/_shared.js";
import { syncReviewScheduleHandler } from "../../src/study/handler.js";
import { clearFirestore, testDb } from "../helpers/emulator.js";

const db = testDb();
const client = { appVersion: "2.0.0", build: 1, platform: "ios" as const };
const u1 = { uid: "u1", signInProvider: "google.com" };
const TOKEN = "fcm-token-".padEnd(60, "a");
const HCM = "Asia/Ho_Chi_Minh";
const NOW = new Date("2026-09-23T03:00:00.000Z"); // 10:00 HCM

function recorder() {
  const sent: PushMessage[] = [];
  return { sent, push: { send: async (ms: PushMessage[]) => { sent.push(...ms); return ms.map((m) => ({ token: m.token, ok: true, unregistered: false })); } } };
}
const makeDeps = (push: Deps["services"]["push"], now = NOW): Deps => unitDeps({ db, now: () => now, services: { push } });

async function seedMinute(id: string, title: string) {
  await db.doc(`users/u1/minutes/${id}`).set({ title, status: "ready", sourceType: "audio", tagIds: [], createdAt: Timestamp.fromDate(NOW), updatedAt: Timestamp.fromDate(NOW) });
}

describe("S11-03b — review schedule sync + due reminders", () => {
  beforeEach(async () => {
    await clearFirestore();
    await db.doc("users/u1").set({ plan: "free" });
    await db.doc(`users/u1/devices/${deviceIdOf(TOKEN)}`).set({ token: TOKEN, platform: "ios", locale: "vi-VN", appVersion: "2.0.0", createdAt: Timestamp.fromDate(NOW), lastSeenAt: Timestamp.fromDate(NOW) });
    await seedMinute("m1", "Bài 3");
    await seedMinute("m2", "Bài 4");
  });

  it("sync stores the schedule under the note with the next reminder at 19:00 local; empty map removes it; unknown note → not-found", async () => {
    const deps = makeDeps(recorder().push);
    const out = await syncReviewScheduleHandler(u1, { client, minuteId: "m1", timezone: HCM, cards: { q1: { r: 0, i: 0, e: 2.5, d: null }, q2: { r: 1, i: 3, e: 2.5, d: "2026-09-26T01:00:00.000Z" } } }, deps);
    expect(out).toEqual({ cardCount: 2, dueCount: 1, nextDueAt: NOW.toISOString(), remindAt: "2026-09-23T12:00:00.000Z" });
    const doc = (await db.doc("users/u1/minutes/m1/study/review").get()).data();
    expect(doc).toMatchObject({ uid: "u1", minuteId: "m1", title: "Bài 3", timezone: HCM, cardCount: 2, dueCount: 1, remindedAt: null });
    expect(doc?.cards.q2.d).toBe("2026-09-26T01:00:00.000Z");

    expect(await syncReviewScheduleHandler(u1, { client, minuteId: "m1", timezone: HCM, cards: {} }, deps)).toEqual({ cardCount: 0, dueCount: 0, nextDueAt: null, remindAt: null });
    expect((await db.doc("users/u1/minutes/m1/study/review").get()).exists).toBe(false);
    await expect(syncReviewScheduleHandler(u1, { client, minuteId: "nope", timezone: HCM, cards: {} }, deps)).rejects.toMatchObject({ code: "not-found" });
  });

  it("the hourly job sends one push per user naming a single note, clears remindAt, and does not repeat until the app syncs again", async () => {
    const rec = recorder();
    const deps = makeDeps(rec.push);
    await syncReviewScheduleHandler(u1, { client, minuteId: "m1", timezone: HCM, cards: { q1: { r: 0, i: 0, e: 2.5, d: null }, q2: { r: 0, i: 0, e: 2.5, d: null } } }, deps);
    // 18:00 HCM: not yet
    expect(await remindDueReviews(makeDeps(rec.push, new Date("2026-09-23T11:00:00Z")))).toEqual({ notes: 0, users: 0, sent: 0, skipped: 0 });
    // 19:05 HCM
    const at = new Date("2026-09-23T12:05:00Z");
    expect(await remindDueReviews(makeDeps(rec.push, at))).toEqual({ notes: 1, users: 1, sent: 1, skipped: 0 });
    expect(rec.sent).toHaveLength(1);
    expect(rec.sent[0]).toMatchObject({ token: TOKEN, title: "Đến giờ ôn tập", body: '2 thẻ đến hạn trong "Bài 3".', data: { type: "reviewDue", minuteId: "m1" }, collapseKey: "review:u1" });
    const doc = (await db.doc("users/u1/minutes/m1/study/review").get()).data();
    expect(doc?.remindAt).toBeNull();
    expect(doc?.remindedAt).toBeInstanceOf(Timestamp);
    // next hour: nothing pending
    expect(await remindDueReviews(makeDeps(rec.push, new Date("2026-09-23T13:05:00Z")))).toEqual({ notes: 0, users: 0, sent: 0, skipped: 0 });
    // the app reviews at 20:00 and syncs → re-armed for tomorrow 19:00
    const again = await syncReviewScheduleHandler(u1, { client, minuteId: "m1", timezone: HCM, cards: { q1: { r: 1, i: 1, e: 2.5, d: "2026-09-24T13:00:00.000Z" }, q2: { r: 1, i: 1, e: 2.5, d: "2026-09-24T13:00:00.000Z" } } }, makeDeps(rec.push, new Date("2026-09-23T13:00:00Z")));
    expect(again.remindAt).toBe("2026-09-25T12:00:00.000Z"); // due 20:00 on the 24th → 19:00 on the 25th
  });

  it("several due notes → one counting push; pref off → skipped but still cleared; deleting the note removes the schedule", async () => {
    const rec = recorder();
    const deps = makeDeps(rec.push);
    const cards = { q: { r: 0, i: 0, e: 2.5, d: null } };
    await syncReviewScheduleHandler(u1, { client, minuteId: "m1", timezone: HCM, cards }, deps);
    await syncReviewScheduleHandler(u1, { client, minuteId: "m2", timezone: HCM, cards: { ...cards, q2: cards.q } }, deps);
    const at = new Date("2026-09-23T12:05:00Z");
    expect(await remindDueReviews(makeDeps(rec.push, at))).toEqual({ notes: 2, users: 1, sent: 1, skipped: 0 });
    expect(rec.sent[0]).toMatchObject({ body: "3 thẻ đến hạn trong 2 ghi chú.", data: { type: "reviewDue" } });
    expect(rec.sent[0]!.data.minuteId).toBeUndefined();

    await db.doc("users/u1").set({ notifications: { reviewReminders: false } }, { merge: true });
    await syncReviewScheduleHandler(u1, { client, minuteId: "m1", timezone: HCM, cards }, deps);
    expect(await remindDueReviews(makeDeps(rec.push, at))).toEqual({ notes: 1, users: 1, sent: 0, skipped: 1 });
    expect((await db.doc("users/u1/minutes/m1/study/review").get()).data()?.remindAt).toBeNull();

    await deleteMinuteHandler(u1, { client, minuteId: "m2" }, unitDeps({ db, bucket: { deleteFiles: async () => undefined } as unknown as Deps["bucket"], now: () => NOW }));
    expect((await db.doc("users/u1/minutes/m2/study/review").get()).exists).toBe(false);
  });
});

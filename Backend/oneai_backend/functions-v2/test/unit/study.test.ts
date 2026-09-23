import { describe, expect, it } from "vitest";
import { reviewDueCopy } from "../../src/push/copy.js";
import { computeRemindAt, groupByUser, localHourOn, summarize } from "../../src/study/schedule.js";
import { SyncReviewScheduleInput } from "../../src/study/types.js";

const HCM = "Asia/Ho_Chi_Minh";
const now = new Date("2026-09-23T03:00:00.000Z"); // 10:00 HCM

describe("review schedule maths (S11-03b)", () => {
  it("summarize: never-reviewed cards are due now, nextDueAt is the earliest", () => {
    const s = summarize({
      a: { r: 0, i: 0, e: 2.5, d: null },
      b: { r: 2, i: 6, e: 2.6, d: "2026-09-25T00:00:00.000Z" },
      c: { r: 1, i: 1, e: 2.5, d: "2026-09-22T00:00:00.000Z" },
    }, now);
    expect(s).toEqual({ cardCount: 3, dueCount: 2, nextDueAt: new Date("2026-09-22T00:00:00.000Z") });
    expect(summarize({}, now)).toEqual({ cardCount: 0, dueCount: 0, nextDueAt: null });
  });

  it("localHourOn: 19:00 local across zones and DST", () => {
    expect(localHourOn(now, HCM, 19).toISOString()).toBe("2026-09-23T12:00:00.000Z");
    expect(localHourOn(new Date("2026-03-29T05:00:00Z"), "Europe/Berlin", 19).toISOString()).toBe("2026-03-29T17:00:00.000Z"); // CEST day
    expect(localHourOn(new Date("2026-03-28T05:00:00Z"), "Europe/Berlin", 19).toISOString()).toBe("2026-03-28T18:00:00.000Z"); // CET day
    expect(localHourOn(new Date("2026-09-23T23:30:00Z"), "America/Los_Angeles", 19).toISOString()).toBe("2026-09-24T02:00:00.000Z");
  });

  it("computeRemindAt: today 19:00 when due already; the due day's 19:00 when later; next day when 19:00 has passed", () => {
    expect(computeRemindAt(now, HCM, now)?.toISOString()).toBe("2026-09-23T12:00:00.000Z");
    expect(computeRemindAt(new Date("2026-09-26T01:00:00Z"), HCM, now)?.toISOString()).toBe("2026-09-26T12:00:00.000Z");
    const evening = new Date("2026-09-23T13:00:00Z"); // 20:00 HCM
    expect(computeRemindAt(evening, HCM, evening)?.toISOString()).toBe("2026-09-24T12:00:00.000Z");
    expect(computeRemindAt(new Date("2026-09-26T12:00:00Z"), HCM, now)?.toISOString()).toBe("2026-09-27T12:00:00.000Z"); // due exactly 19:00 → next day
    expect(computeRemindAt(null, HCM, now)).toBeNull();
  });

  it("groupByUser: one group per user with the summed count, insertion order kept", () => {
    const g = groupByUser([
      { uid: "u1", minuteId: "a", title: "A", dueCount: 3 },
      { uid: "u2", minuteId: "b", title: "B", dueCount: 1 },
      { uid: "u1", minuteId: "c", title: "C", dueCount: 2 },
    ]);
    expect(g.map((x) => [x.uid, x.dueCount, x.notes.length])).toEqual([["u1", 5, 2], ["u2", 1, 1]]);
  });

  it("copy: one note names it, several count; locale fallback", () => {
    expect(reviewDueCopy("vi-VN", 4, 1, "Bài 3")).toEqual({ title: "Đến giờ ôn tập", body: '4 thẻ đến hạn trong "Bài 3".' });
    expect(reviewDueCopy("en", 1, 1, "")).toEqual({ title: "Time to review", body: '1 card is due in "Untitled".' });
    expect(reviewDueCopy("pt-BR", 7, 3, "x").body).toBe("7 cards are due across 3 notes.");
  });

  it("input: ≤200 cards, question ≤500 chars, ISO dates with offset, strict card shape", () => {
    const client = { appVersion: "2.0.0", build: 1, platform: "ios" as const };
    const ok = SyncReviewScheduleInput.safeParse({ client, minuteId: "m", timezone: HCM, cards: { q: { r: 1, i: 1, e: 2.5, d: "2026-09-23T03:00:00.000Z" } } });
    expect(ok.success).toBe(true);
    expect(SyncReviewScheduleInput.safeParse({ client, minuteId: "m", timezone: HCM, cards: { q: { r: 1, i: 1, e: 2.5, d: "tomorrow" } } }).success).toBe(false);
    expect(SyncReviewScheduleInput.safeParse({ client, minuteId: "m", timezone: HCM, cards: { q: { r: 1, i: 1, e: 2.5, d: null, x: 1 } } }).success).toBe(false);
    expect(SyncReviewScheduleInput.safeParse({ client, minuteId: "m", timezone: "Mars/Olympus", cards: {} }).success).toBe(false);
    const many = Object.fromEntries(Array.from({ length: 201 }, (_, i) => [`q${i}`, { r: 0, i: 0, e: 2.5, d: null }]));
    expect(SyncReviewScheduleInput.safeParse({ client, minuteId: "m", timezone: HCM, cards: many }).success).toBe(false);
  });
});

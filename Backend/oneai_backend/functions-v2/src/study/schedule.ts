/** Pure scheduling maths for review reminders — no Firestore, no clock. */
import type { CardSchedule } from "./types.js";

export const REMIND_HOUR_LOCAL = 19;

export interface ScheduleSummary { cardCount: number; dueCount: number; nextDueAt: Date | null }

/** A card with no `d` is due now; otherwise it is due at `d`. */
export function summarize(cards: Record<string, CardSchedule>, now: Date): ScheduleSummary {
  let dueCount = 0;
  let next: Date | null = null;
  for (const c of Object.values(cards)) {
    const due = c.d ? new Date(c.d) : now;
    if (due.getTime() <= now.getTime()) dueCount++;
    if (next === null || due.getTime() < next.getTime()) next = due;
  }
  return { cardCount: Object.keys(cards).length, dueCount, nextDueAt: next };
}

/** Wall-clock parts of `d` in `timeZone`. */
function localParts(d: Date, timeZone: string): { y: number; m: number; day: number; h: number } {
  const p = Object.fromEntries(
    new Intl.DateTimeFormat("en-US", { timeZone, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit" })
      .formatToParts(d).filter((x) => x.type !== "literal").map((x) => [x.type, Number(x.value)]),
  ) as Record<string, number>;
  return { y: p.year!, m: p.month!, day: p.day!, h: p.hour! };
}

/**
 * The instant of `hour`:00 on the local date of `d` in `timeZone`. Found by
 * probing around the UTC guess, which stays correct across DST changes.
 */
export function localHourOn(d: Date, timeZone: string, hour: number): Date {
  const { y, m, day } = localParts(d, timeZone);
  let guess = Date.UTC(y, m - 1, day, hour);
  for (let i = 0; i < 4; i++) {
    const p = localParts(new Date(guess), timeZone);
    const offsetH = (Date.UTC(p.y, p.m - 1, p.day, p.h) - guess) / 3_600_000;
    if (p.y === y && p.m === m && p.day === day && p.h === hour) break;
    guess -= offsetH * 3_600_000;
  }
  return new Date(guess);
}

/**
 * The next reminder moment: the first 19:00 local that is both after `now`
 * and not before the first due card. A note with nothing scheduled gets
 * none. One reminder per sync — the app syncs after every review session,
 * which re-arms it — so a user who ignores the push is not nagged daily.
 */
export function computeRemindAt(nextDueAt: Date | null, timeZone: string, now: Date, hour = REMIND_HOUR_LOCAL): Date | null {
  if (nextDueAt === null) return null;
  const earliest = nextDueAt.getTime() > now.getTime() ? nextDueAt : now;
  let t = localHourOn(earliest, timeZone, hour);
  if (t.getTime() <= earliest.getTime()) t = localHourOn(new Date(earliest.getTime() + 24 * 3_600_000), timeZone, hour);
  return t;
}

export interface DueNote { uid: string; minuteId: string; title: string; dueCount: number }
export interface DueGroup { uid: string; notes: DueNote[]; dueCount: number }

/** One push per user, however many notes are due. Deterministic order for tests. */
export function groupByUser(notes: DueNote[]): DueGroup[] {
  const m = new Map<string, DueGroup>();
  for (const n of notes) {
    const g = m.get(n.uid) ?? { uid: n.uid, notes: [], dueCount: 0 };
    g.notes.push(n);
    g.dueCount += n.dueCount;
    m.set(n.uid, g);
  }
  return [...m.values()];
}

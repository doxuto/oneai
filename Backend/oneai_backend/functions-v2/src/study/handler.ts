import { FieldValue, Timestamp, type DocumentReference, type Firestore } from "firebase-admin/firestore";
import type { Deps } from "../lib/deps.js";
import { rethrow } from "../lib/errors.js";
import { requireCaller, type Caller } from "../lib/handler.js";
import { logDone } from "../lib/logging.js";
import { toIso } from "../lib/time.js";
import { parse } from "../lib/validate.js";
import { loadOwnedMinute } from "../minutes/_shared.js";
import { computeRemindAt, summarize } from "./schedule.js";
import { SyncReviewScheduleInput, type SyncReviewScheduleOutput } from "./types.js";

export const reviewRef = (db: Firestore, uid: string, minuteId: string): DocumentReference =>
  db.doc(`users/${uid}/minutes/${minuteId}/study/review`);

/**
 * Whole-schedule upsert: the app owns the SM-2 state and sends the full map
 * after a session; last write wins across devices (the review sessions of one
 * person do not overlap in practice). Empty map = stop tracking.
 */
export async function syncReviewScheduleHandler(caller: Caller | undefined, raw: unknown, deps: Deps): Promise<SyncReviewScheduleOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(SyncReviewScheduleInput, raw, deps.minClientVersion);
  try {
    const { doc } = await loadOwnedMinute(deps.db, uid, input.minuteId);
    const ref = reviewRef(deps.db, uid, input.minuteId);
    const now = deps.now();
    const s = summarize(input.cards, now);
    if (s.cardCount === 0) {
      await ref.delete();
      logDone("study.sync", startedAt, { uid, minuteId: input.minuteId, cards: 0 });
      return { cardCount: 0, dueCount: 0, nextDueAt: null, remindAt: null };
    }
    const remindAt = computeRemindAt(s.nextDueAt, input.timezone, now);
    await ref.set({
      uid,
      minuteId: input.minuteId,
      title: doc.title ?? "",
      timezone: input.timezone,
      cards: input.cards,
      cardCount: s.cardCount,
      dueCount: s.dueCount,
      nextDueAt: s.nextDueAt ? Timestamp.fromDate(s.nextDueAt) : null,
      remindAt: remindAt ? Timestamp.fromDate(remindAt) : null,
      remindedAt: null,
      updatedAt: FieldValue.serverTimestamp(),
    });
    logDone("study.sync", startedAt, { uid, minuteId: input.minuteId, cards: s.cardCount, due: s.dueCount });
    return { cardCount: s.cardCount, dueCount: s.dueCount, nextDueAt: toIso(s.nextDueAt), remindAt: toIso(remindAt) };
  } catch (err) {
    return rethrow(err, "study.sync.failed", { uid, minuteId: input.minuteId });
  }
}

import { z } from "zod";
import { DocId, IanaTimezone, withClient } from "../types/common.js";

/**
 * S11-03b — the app's SM-2 schedule for one note's flashcards, mirrored on the
 * server so (a) a reinstall / second phone keeps the progress and (b) the
 * reminder job can push "N cards are due". The app stays the scheduler: the
 * server only stores what it sends and derives the next reminder moment.
 */
export const CardSchedule = z.object({
  /** consecutive successful reviews */
  r: z.number().int().min(0).max(10_000),
  /** interval in days */
  i: z.number().int().min(0).max(36_500),
  /** easiness factor */
  e: z.number().min(1.3).max(10),
  /** next review, ISO-8601; null = never reviewed (due now) */
  d: z.string().datetime({ offset: true }).nullable(),
}).strict();
export type CardSchedule = z.infer<typeof CardSchedule>;

export const MAX_CARDS_PER_NOTE = 200;
export const MAX_QUESTION_CHARS = 500;

export const SyncReviewScheduleInput = withClient({
  minuteId: DocId,
  /** The phone's zone: reminders go out at 19:00 local. */
  timezone: IanaTimezone,
  /** keyed by the card's question text (stable across regenerations). Empty = stop tracking this note. */
  cards: z.record(z.string().min(1).max(MAX_QUESTION_CHARS), CardSchedule)
    .refine((m) => Object.keys(m).length <= MAX_CARDS_PER_NOTE, { message: `at most ${MAX_CARDS_PER_NOTE} cards` }),
}).strict();
export type SyncReviewScheduleInput = z.infer<typeof SyncReviewScheduleInput>;

export interface SyncReviewScheduleOutput {
  cardCount: number;
  dueCount: number;
  nextDueAt: string | null;
  /** When the next "cards due" push is planned, null when nothing is pending. */
  remindAt: string | null;
}

/** users/{uid}/minutes/{minuteId}/study/review — server-only writes, owner reads. */
export interface ReviewDoc {
  uid: string;
  minuteId: string;
  title: string;
  timezone: string;
  cards: Record<string, CardSchedule>;
  cardCount: number;
  dueCount: number;
  nextDueAt: FirebaseFirestore.Timestamp | null;
  remindAt: FirebaseFirestore.Timestamp | null;
  remindedAt: FirebaseFirestore.Timestamp | null;
  updatedAt: FirebaseFirestore.Timestamp;
}

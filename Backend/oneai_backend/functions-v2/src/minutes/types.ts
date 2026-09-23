import { z } from "zod";
import { Cursor, DocId, ShortText, withClient } from "../types/common.js";

// ---------- enums (string literals on the wire, never integers) ----------

export const SourceType = z.enum(["audio", "pdf"]);
export type SourceType = z.infer<typeof SourceType>;

export const MinuteStatus = z.enum([
  "uploading",
  "queued",
  "transcribing",
  "summarizing",
  "ready",
  "failed",
  "cancelled",
]);
export type MinuteStatus = z.infer<typeof MinuteStatus>;

export const ListSort = z.enum(["createdAtDesc", "titleAsc"]);
export type ListSort = z.infer<typeof ListSort>;

// ---------- limits ----------

/** Must agree with storage.rules (`request.resource.size < 300 * 1024 * 1024`). */
export const MAX_SOURCE_BYTES = 300 * 1024 * 1024;
export const MAX_TAGS_PER_MINUTE = 10;

// ---------- inputs ----------

export const CreateMinuteInput = withClient({
  sourceType: SourceType,
  fileName: z.string().min(1).max(200),
  sizeBytes: z.number().int().min(1).max(MAX_SOURCE_BYTES),
  contentType: z.string().min(3).max(100),
}).strict();
export type CreateMinuteInput = z.infer<typeof CreateMinuteInput>;

export const ListMinutesInput = withClient({
  limit: z.number().int().min(1).max(50).default(20),
  cursor: Cursor.optional(),
  tagIds: z.array(DocId).max(MAX_TAGS_PER_MINUTE).optional(),
  sort: ListSort.default("createdAtDesc"),
});
export type ListMinutesInput = z.infer<typeof ListMinutesInput>;

export const GetMinuteInput = withClient({ minuteId: DocId });
export type GetMinuteInput = z.infer<typeof GetMinuteInput>;

export const UpdateMinuteInput = withClient({
  minuteId: DocId,
  title: ShortText.min(1).optional(),
  // One emoji is up to ~8 UTF-16 code units (ZWJ sequences, skin tones).
  iconEmoji: z.string().min(1).max(16).nullable().optional(),
  tagIds: z.array(DocId).max(MAX_TAGS_PER_MINUTE).optional(),
})
  .strict()
  .refine((v) => v.title !== undefined || v.iconEmoji !== undefined || v.tagIds !== undefined, {
    message: "At least one of title, iconEmoji, tagIds is required",
  });
export type UpdateMinuteInput = z.infer<typeof UpdateMinuteInput>;

export const DeleteMinuteInput = withClient({ minuteId: DocId });
export type DeleteMinuteInput = z.infer<typeof DeleteMinuteInput>;

// ---------- outputs (plain interfaces; dates are ISO strings) ----------

export interface MinuteSummary {
  id: string;
  title: string;
  iconEmoji: string | null;
  sourceType: SourceType;
  contentKind: string | null;
  status: MinuteStatus;
  durationSeconds: number | null;
  tagIds: string[];
  createdAt: string;
  updatedAt: string;
}

export interface SummarySection {
  title: string;
  bullets: string[];
}

export interface Summary {
  title: string;
  text: string;
  icon: string | null;
  sections: SummarySection[];
}

export interface TranscriptSegment {
  startSeconds: number;
  endSeconds: number;
  text: string;
  speakerId: string;
  speakerLabel: string;
}

export interface Transcript {
  durationSeconds: number;
  languageCode: string | null;
  languageProbability: number | null;
  text: string;
  segments: TranscriptSegment[];
}

export interface Speaker {
  id: string;
  label: string;
}

export interface MinuteFailure {
  code: string;
  message: string;
}

/** An event the summariser (or `generateCalendarEvents`) extracted from the content. */
export interface CalendarEvent {
  id: string;
  title: string;
  description: string;
  /** ISO-8601 when resolvable, else the text as spoken. */
  datetime: string;
  participants: string[];
  rawText: string;
}

export const ARTIFACT_KINDS = ["shortQuestions", "quiz", "flashcards", "mindmap", "speakers", "calendarEvents"] as const;
export type ArtifactKind = (typeof ARTIFACT_KINDS)[number];

export interface MinuteDetail extends MinuteSummary {
  summary: Summary | null;
  transcript: Transcript | null;
  /** Storage path of the source file; the client resolves a download URL with its own auth. */
  sourcePath: string | null;
  speakers: Speaker[];
  failure: MinuteFailure | null;
  description: string | null;
  keywords: string[];
  summaryLanguage: string | null;
  /** Extracted at summarise time; regenerate with `generateCalendarEvents`. */
  calendarEvents: CalendarEvent[];
  /** Which `artifacts/{kind}` docs exist, so the app can show tabs without a generate call. */
  availableArtifacts: ArtifactKind[];
}

export interface CreateMinuteOutput {
  minuteId: string;
  upload: {
    /** Upload here with the Firebase Storage SDK; storage.rules enforce size and type. */
    path: string;
    contentType: string;
    maxSizeBytes: number;
  };
}

export interface ListMinutesOutput {
  items: MinuteSummary[];
  nextCursor: string | null;
}

export interface GetMinuteOutput {
  minute: MinuteDetail;
}

export interface UpdateMinuteOutput {
  minute: MinuteSummary;
}

export type DeleteMinuteOutput = Record<string, never>;

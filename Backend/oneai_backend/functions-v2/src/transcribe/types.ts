import { z } from "zod";
import { MinuteTemplate } from "../prompts/templates.js";
import { DocId, IanaTimezone, withClient } from "../types/common.js";
import type { MinuteStatus } from "../minutes/types.js";

export const TASK_QUEUE = "processTranscription";

export const StartTranscriptionInput = withClient({
  minuteId: DocId,
  /** Client-generated UUID; a retry with the same id returns the same job. */
  requestId: z.string().uuid(),
  audioLanguage: z.string().max(35).default("auto"),
  summaryLanguage: z.string().min(2).max(35),
  keywords: z.array(z.string().min(1).max(60)).max(20).default([]),
  description: z.string().max(500).optional(),
  /** Shapes the summary's sections (S11-08). */
  template: MinuteTemplate.default("auto"),
  timezone: IanaTimezone,
  /** Client's best guess, untrusted; the worker measures the real one. */
  durationSeconds: z.number().min(0).max(24 * 3600).optional(),
}).strict();
export type StartTranscriptionInput = z.infer<typeof StartTranscriptionInput>;

export interface StartTranscriptionOutput {
  minuteId: string;
  status: MinuteStatus;
  /** True when this call did nothing because requestId was already processed. */
  duplicate: boolean;
}

export const CancelTranscriptionInput = withClient({ minuteId: DocId }).strict();
export type CancelTranscriptionOutput = Record<string, never>;

/** Payload carried by the Cloud Task. Re-validated in the worker. */
export const TaskPayload = z.object({
  uid: DocId,
  minuteId: DocId,
  jobId: DocId,
});
export type TaskPayload = z.infer<typeof TaskPayload>;

/** transcriptionJobs/{jobId} — server-only. */
export interface JobDoc {
  uid: string;
  minuteId: string;
  requestId: string;
  state: "queued" | "running" | "done" | "failed" | "cancelled";
  attempt: number;
  periodId: string;
  /** Seconds reserved at start, settled to the measured length by the worker. */
  chargedSeconds: number;
  quotaRefunded: boolean;
  options: {
    audioLanguage: string;
    summaryLanguage: string;
    keywords: string[];
    description: string | null;
    template?: string;
    timezone: string;
  };
  createdAt: FirebaseFirestore.Timestamp;
  startedAt?: FirebaseFirestore.Timestamp;
  finishedAt?: FirebaseFirestore.Timestamp;
  error?: { code: string; message: string } | null;
}

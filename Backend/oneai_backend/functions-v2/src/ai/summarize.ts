import { z } from "zod";
import type { LlmClient } from "../lib/llm/types.js";
import { SUMMARIZE_PROMPT, SUMMARIZE_SYSTEM, fill } from "../prompts/summarize.js";
import { templateGuidance, type MinuteTemplate } from "../prompts/templates.js";
import type { Summary } from "../minutes/types.js";

export const ContentKind = z.enum([
  "interview", "podcast", "team_meeting", "lecture", "presentation", "webinar", "casual_talk", "other",
]);

export const CalendarEvent = z.object({
  id: z.string().min(1).max(64),
  title: z.string().max(200),
  description: z.string().max(1000),
  datetime: z.string().max(40),
  participants: z.array(z.string().max(100)).max(20),
  rawText: z.string().max(1000),
});
export type CalendarEvent = z.infer<typeof CalendarEvent>;

export const SummarizeOutput = z.object({
  contentKind: ContentKind,
  title: z.string().min(1).max(200),
  text: z.string().max(8000),
  sections: z.array(z.object({
    title: z.string().max(200),
    bullets: z.array(z.string().max(1000)).max(40),
  })).max(60),
  iconEmoji: z.string().min(1).max(16),
  calendarEvents: z.array(CalendarEvent).max(20),
});
export type SummarizeOutput = z.infer<typeof SummarizeOutput>;

export interface SummarizeInput {
  transcript: string;
  summaryLanguage: string;
  description: string | null;
  now: Date;
  timezone: string;
  /** S11-08; undefined/"auto" = generic guidance. */
  template?: MinuteTemplate | null;
}

/** Transcripts longer than this are trimmed from the middle to protect the token budget (S4-07). */
const MAX_TRANSCRIPT_CHARS = 120_000;

export function trimTranscript(text: string, max = MAX_TRANSCRIPT_CHARS): string {
  if (text.length <= max) return text;
  const half = Math.floor(max / 2);
  return `${text.slice(0, half)}\n\n[… ${text.length - max} characters omitted …]\n\n${text.slice(-half)}`;
}

export async function summarizeTranscript(
  llm: LlmClient,
  input: SummarizeInput,
  signal?: AbortSignal,
): Promise<{ summary: Summary; contentKind: string; iconEmoji: string; title: string; calendarEvents: CalendarEvent[]; model: string; tokens: { input: number; output: number } }> {
  const prompt = fill(SUMMARIZE_PROMPT, {
    transcript: trimTranscript(input.transcript),
    description: input.description ?? "",
    templateGuidance: templateGuidance(input.template),
    now: input.now.toISOString(),
    timezone: input.timezone,
    summaryLanguage: input.summaryLanguage,
  });

  const { data, model, tokens } = await llm.generateJson(
    { name: "summarize", system: SUMMARIZE_SYSTEM, prompt, schema: SummarizeOutput, maxOutputTokens: 4000, temperature: 0.2 },
    signal,
  );

  return {
    summary: { title: data.title, text: data.text, icon: data.iconEmoji, sections: data.sections },
    contentKind: data.contentKind,
    iconEmoji: data.iconEmoji,
    title: data.title,
    calendarEvents: data.calendarEvents,
    model,
    tokens,
  };
}

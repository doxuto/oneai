import { z } from "zod";
import { LanguageCode, LongText, withClient } from "../types/common.js";
import type { ChatTurn } from "../lib/llm/types.js";

export const SearchNotesInput = withClient({
  query: z.string().trim().min(1).max(500),
  limit: z.number().int().min(1).max(30).default(20),
}).strict();
export type SearchNotesInput = z.infer<typeof SearchNotesInput>;

export interface SearchHit { minuteId: string; title: string; iconEmoji: string | null; createdAt: string | null; score: number }
export interface SearchNotesOutput { items: SearchHit[] }

const Turn = z.object({ role: z.enum(["user", "assistant"]), text: z.string().max(4000) });

export const AskAllInput = withClient({
  question: LongText.min(1),
  languageCode: LanguageCode.default("en"),
  /** Prior turns of this ask-all session (client keeps them; nothing is stored server-side). */
  history: z.array(Turn).max(8).default([]),
}).strict();
export type AskAllInput = z.infer<typeof AskAllInput>;

export interface AskAllSource { minuteId: string; title: string; iconEmoji: string | null; createdAt: string | null }
export interface AskAllOutput { answer: string; sources: AskAllSource[] }
export type { ChatTurn };

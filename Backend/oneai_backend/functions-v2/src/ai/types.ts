import { z } from "zod";
import { DocId, LanguageCode, LongText, withClient } from "../types/common.js";

// ---------- inputs ----------
const ForMinute = { minuteId: DocId, languageCode: LanguageCode.default("en") };

export const GenerateInput = withClient({ ...ForMinute, force: z.boolean().default(false) }).strict();
export type GenerateInput = z.infer<typeof GenerateInput>;

export const ChatInput = withClient({ ...ForMinute, question: LongText.min(1) }).strict();
export type ChatInput = z.infer<typeof ChatInput>;

export const ListChatMessagesInput = withClient({
  minuteId: DocId,
  limit: z.number().int().min(1).max(100).default(50),
  cursor: z.string().max(512).optional(),
});

export const MapSpeakersInput = withClient({ minuteId: DocId, force: z.boolean().default(false) }).strict();
export const RenameSpeakerInput = withClient({
  minuteId: DocId,
  speakerId: z.string().regex(/^speaker_\d+$|^document$/),
  name: z.string().trim().min(1).max(60),
}).strict();

// ---------- LLM output schemas (also the stored artifact shape) ----------
export const ShortQuestionsData = z.object({ questions: z.array(z.string().min(1).max(300)).min(1).max(10) });
export type ShortQuestionsData = z.infer<typeof ShortQuestionsData>;

export const QuizData = z.object({
  items: z.array(z.object({
    question: z.string().min(1).max(500),
    options: z.array(z.string().min(1).max(300)).min(2).max(4),
    answerIndex: z.number().int().min(0).max(3),
  })).min(1).max(15),
}).refine((q) => q.items.every((i) => i.answerIndex < i.options.length), "answerIndex out of range");
export type QuizData = z.infer<typeof QuizData>;

export const FlashcardsData = z.object({
  items: z.array(z.object({ question: z.string().min(1).max(500), answer: z.string().min(1).max(1000) })).min(1).max(15),
});
export type FlashcardsData = z.infer<typeof FlashcardsData>;

// Recursive types cannot be expressed to the JSON-schema converter without $ref,
// so the depth is explicit: root → topic → sub-topic → detail.
const Leaf = z.object({ id: z.string().min(1).max(16), title: z.string().min(1).max(200) });
const L3 = Leaf.extend({ children: z.array(Leaf).max(12).default([]) });
const L2 = Leaf.extend({ children: z.array(L3).max(12).default([]) });
export const MindmapData = z.object({
  root: Leaf.extend({ icon: z.string().min(1).max(16), children: z.array(L2).min(1).max(12) }),
});
export type MindmapData = z.infer<typeof MindmapData>;

export const SpeakersData = z.object({
  speakers: z.array(z.object({ id: z.string().regex(/^speaker_\d+$|^document$/), label: z.string().min(1).max(60) })).min(1).max(30),
});
export type SpeakersData = z.infer<typeof SpeakersData>;

// ---------- outputs ----------
export interface ChatMessage { id: string; role: "user" | "assistant"; text: string; createdAt: string }
export interface ChatOutput { answer: string; messageId: string }
export interface ListChatMessagesOutput { items: ChatMessage[]; nextCursor: string | null }
export interface GenerateOutput<T> { data: T; cached: boolean }

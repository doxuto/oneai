import { HttpsError } from "firebase-functions/v2/https";
import type { ZodType, ZodTypeDef } from "zod";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { decodeCursor, encodeCursor } from "../lib/cursor.js";
import type { Deps } from "../lib/deps.js";
import { rethrow } from "../lib/errors.js";
import { requireCaller, type Caller } from "../lib/handler.js";
import { logDone } from "../lib/logging.js";
import { toIso } from "../lib/time.js";
import { parse } from "../lib/validate.js";
import { loadOwnedMinute } from "../minutes/_shared.js";
import {
  CALENDAR_EVENTS_PROMPT, CHAT_CONTEXT, CHAT_SYSTEM, FLASHCARDS_PROMPT, MAP_SPEAKERS_PROMPT, MAP_SPEAKERS_SYSTEM, MINDMAP_PROMPT, QUIZ_PROMPT, SHORT_QUESTIONS_PROMPT,
} from "../prompts/ai.js";
import { fill } from "../prompts/summarize.js";
import { artifactRef, chargeAiCall, generateArtifact, loadReadyTranscript, promptTranscript, transcriptBySpeaker } from "./_artifacts.js";
import {
  CalendarEventsData, ChatInput, FlashcardsData, GenerateCalendarEventsInput, GenerateInput, ListChatMessagesInput, MapSpeakersInput, MindmapData, QuizData,
  RenameSpeakerInput, ShortQuestionsData, SpeakersData,
  type ChatMessage, type ChatOutput, type GenerateOutput, type ListChatMessagesOutput,
} from "./types.js";

// ---------------------------------------------------------------- generate*

type Gen<T> = (caller: Caller | undefined, raw: unknown, deps: Deps) => Promise<GenerateOutput<T>>;

function makeGenerator<T>(kind: "shortQuestions" | "quiz" | "flashcards" | "mindmap", schema: ZodType<T, ZodTypeDef, unknown>, template: string, maxOutputTokens: number): Gen<T> {
  return async (caller, raw, deps) => {
    const startedAt = Date.now();
    const { uid } = requireCaller(caller);
    const input = parse(GenerateInput, raw, deps.minClientVersion);
    try {
      const loaded = await loadReadyTranscript(deps, uid, input.minuteId);
      const prompt = fill(template, { transcript: promptTranscript(loaded.transcript), languageCode: input.languageCode });
      const out = await generateArtifact<T>({ deps, llm: deps.services.llm, uid, loaded, kind, schema, prompt, maxOutputTokens, force: input.force });
      logDone(`ai.${kind}`, startedAt, { uid, minuteId: input.minuteId, cached: out.cached });
      return out;
    } catch (err) {
      return rethrow(err, `ai.${kind}.failed`, { uid, minuteId: input.minuteId });
    }
  };
}

export const generateShortQuestionsHandler = makeGenerator<ShortQuestionsData>("shortQuestions", ShortQuestionsData, SHORT_QUESTIONS_PROMPT, 800);
export const generateQuizHandler = makeGenerator<QuizData>("quiz", QuizData, QUIZ_PROMPT, 2500);
export const generateFlashcardsHandler = makeGenerator<FlashcardsData>("flashcards", FlashcardsData, FLASHCARDS_PROMPT, 2500);
export const generateMindmapHandler = makeGenerator<MindmapData>("mindmap", MindmapData, MINDMAP_PROMPT, 3000);

// ---------------------------------------------------------------- calendar events

/**
 * The summariser already extracts events at ingest; this regenerates them on
 * demand (different language, or the user wants another pass). Same cache
 * rules as the other artifacts; the ingest-time doc has no sourceHash, so the
 * first explicit call always generates.
 */
export async function generateCalendarEventsHandler(
  caller: Caller | undefined,
  raw: unknown,
  deps: Deps,
): Promise<GenerateOutput<CalendarEventsData>> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(GenerateCalendarEventsInput, raw, deps.minClientVersion);
  try {
    const loaded = await loadReadyTranscript(deps, uid, input.minuteId);
    const storedTz = loaded.minuteDoc.timezone;
    const timezone = input.timezone ?? (typeof storedTz === "string" && storedTz ? storedTz : "UTC");
    const prompt = fill(CALENDAR_EVENTS_PROMPT, {
      transcript: promptTranscript(loaded.transcript),
      languageCode: input.languageCode,
      now: deps.now().toISOString(),
      timezone,
    });
    const out = await generateArtifact<CalendarEventsData>({
      deps, llm: deps.services.llm, uid, loaded, kind: "calendarEvents", schema: CalendarEventsData, prompt, maxOutputTokens: 2000, force: input.force,
    });
    logDone("ai.calendarEvents", startedAt, { uid, minuteId: input.minuteId, cached: out.cached, count: out.data.events.length });
    return out;
  } catch (err) {
    return rethrow(err, "ai.calendarEvents.failed", { uid, minuteId: input.minuteId });
  }
}

// ---------------------------------------------------------------- speakers

export async function mapSpeakersHandler(caller: Caller | undefined, raw: unknown, deps: Deps): Promise<GenerateOutput<SpeakersData>> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(MapSpeakersInput, raw, deps.minClientVersion);
  try {
    const loaded = await loadReadyTranscript(deps, uid, input.minuteId);
    const ids = [...new Set(loaded.transcript.segments.map((s) => s.speakerId))];
    if (ids.length === 0) throw new HttpsError("failed-precondition", "No speakers in this note", { reason: "noSpeakers" });

    // A single voice (or a PDF) needs no model call.
    if (ids.length === 1) {
      const data: SpeakersData = { speakers: [{ id: ids[0]!, label: ids[0] === "document" ? "Document" : "Speaker 1" }] };
      const ref = artifactRef(loaded.minuteRef, "speakers");
      const cur = (await ref.get()).data() as { sourceHash?: string } | undefined;
      if (cur?.sourceHash !== loaded.sourceHash) {
        await ref.set({ kind: "speakers", data, model: null, sourceHash: loaded.sourceHash, generatedAt: FieldValue.serverTimestamp() });
      }
      return { data, cached: cur?.sourceHash === loaded.sourceHash };
    }

    const prompt = fill(MAP_SPEAKERS_PROMPT, { speakerIds: ids.join(", "), transcript: transcriptBySpeaker(loaded.transcript) });
    const out = await generateArtifact<SpeakersData>({
      deps, llm: deps.services.llm, uid, loaded, kind: "speakers", schema: SpeakersData, prompt, system: MAP_SPEAKERS_SYSTEM, maxOutputTokens: 600, force: input.force,
    });
    // Guarantee every id is present exactly once, whatever the model returned.
    const byId = new Map(out.data.speakers.map((s) => [s.id, s.label]));
    const speakers = ids.map((id) => ({ id, label: byId.get(id) ?? id }));
    if (speakers.some((s, i) => s.label !== out.data.speakers[i]?.label || s.id !== out.data.speakers[i]?.id)) {
      await artifactRef(loaded.minuteRef, "speakers").update({ data: { speakers } });
    }
    logDone("ai.mapSpeakers", startedAt, { uid, minuteId: input.minuteId, cached: out.cached, count: speakers.length });
    return { data: { speakers }, cached: out.cached };
  } catch (err) {
    return rethrow(err, "ai.mapSpeakers.failed", { uid, minuteId: input.minuteId });
  }
}

export async function renameSpeakerHandler(caller: Caller | undefined, raw: unknown, deps: Deps): Promise<GenerateOutput<SpeakersData>> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(RenameSpeakerInput, raw, deps.minClientVersion);
  try {
    const { ref: minuteRef } = await loadOwnedMinute(deps.db, uid, input.minuteId);
    const ref = artifactRef(minuteRef, "speakers");
    const data = await deps.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const cur = snap.exists ? SpeakersData.safeParse((snap.data() as { data?: unknown }).data) : undefined;
      const speakers = cur?.success ? [...cur.data.speakers] : [];
      const idx = speakers.findIndex((s) => s.id === input.speakerId);
      if (idx >= 0) speakers[idx] = { id: input.speakerId, label: input.name };
      else speakers.push({ id: input.speakerId, label: input.name });
      const next: SpeakersData = { speakers };
      tx.set(ref, { kind: "speakers", data: next, renamedAt: FieldValue.serverTimestamp() }, { merge: true });
      return next;
    });
    logDone("ai.renameSpeaker", startedAt, { uid, minuteId: input.minuteId });
    return { data, cached: false };
  } catch (err) {
    return rethrow(err, "ai.renameSpeaker.failed", { uid, minuteId: input.minuteId });
  }
}

// ---------------------------------------------------------------- chat

const CHAT_HISTORY_TURNS = 8;

export async function chatHandler(
  caller: Caller | undefined,
  raw: unknown,
  deps: Deps,
  onDelta?: (delta: string) => void,
): Promise<ChatOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(ChatInput, raw, deps.minClientVersion);
  try {
    const loaded = await loadReadyTranscript(deps, uid, input.minuteId);
    const chatCol = loaded.minuteRef.collection("chat");

    const recent = await chatCol.orderBy("createdAt", "desc").limit(CHAT_HISTORY_TURNS).get();
    const history = recent.docs.reverse()
      .map((d) => d.data() as { role?: string; text?: string })
      .filter((m): m is { role: "user" | "assistant"; text: string } => (m.role === "user" || m.role === "assistant") && typeof m.text === "string");

    await chargeAiCall(deps, uid);
    const userRef = chatCol.doc();
    await userRef.set({ role: "user", text: input.question, createdAt: FieldValue.serverTimestamp() });

    const { text, model, tokens } = await deps.services.llm.streamText(
      {
        name: "chat",
        system: fill(CHAT_SYSTEM, { languageCode: input.languageCode }) + "\n\n" + fill(CHAT_CONTEXT, { transcript: promptTranscript(loaded.transcript) }),
        history,
        prompt: input.question,
        maxOutputTokens: 1200,
      },
      onDelta ?? (() => undefined),
    );

    const assistantRef = chatCol.doc();
    await assistantRef.set({ role: "assistant", text, model, tokenCount: tokens.output, createdAt: FieldValue.serverTimestamp() });
    logDone("ai.chat", startedAt, { uid, minuteId: input.minuteId, model, tokensIn: tokens.input, tokensOut: tokens.output });
    return { answer: text, messageId: assistantRef.id };
  } catch (err) {
    return rethrow(err, "ai.chat.failed", { uid, minuteId: input.minuteId });
  }
}

export async function listChatMessagesHandler(caller: Caller | undefined, raw: unknown, deps: Deps): Promise<ListChatMessagesOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(ListChatMessagesInput, raw, deps.minClientVersion);
  try {
    const { ref } = await loadOwnedMinute(deps.db, uid, input.minuteId);
    let q = ref.collection("chat").orderBy("createdAt", "asc").orderBy("__name__", "asc");
    if (input.cursor) {
      const parts = decodeCursor(input.cursor);
      if (parts.length !== 2 || typeof parts[0] !== "number" || typeof parts[1] !== "string") throw new HttpsError("invalid-argument", "Invalid cursor");
      q = q.startAfter(Timestamp.fromMillis(parts[0]), parts[1]);
    }
    const snap = await q.limit(input.limit + 1).get();
    const docs = snap.docs.slice(0, input.limit);
    const items: ChatMessage[] = docs.map((d) => {
      const m = d.data() as { role?: string; text?: string; createdAt?: Timestamp };
      return { id: d.id, role: m.role === "assistant" ? "assistant" : "user", text: typeof m.text === "string" ? m.text : "", createdAt: toIso(m.createdAt ?? null) ?? "1970-01-01T00:00:00.000Z" };
    });
    let nextCursor: string | null = null;
    if (snap.docs.length > input.limit) {
      const last = docs[docs.length - 1];
      const ts = (last?.data() as { createdAt?: Timestamp }).createdAt;
      nextCursor = encodeCursor([ts ? ts.toMillis() : 0, last?.id ?? ""]);
    }
    logDone("ai.chat.list", startedAt, { uid, minuteId: input.minuteId, count: items.length });
    return { items, nextCursor };
  } catch (err) {
    return rethrow(err, "ai.chat.list.failed", { uid, minuteId: input.minuteId });
  }
}

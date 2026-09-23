import { describe, expect, it } from "vitest";
import { openAiClient } from "../../src/lib/llm/openai.js";
import { geminiClient } from "../../src/lib/llm/gemini.js";
import { sseData } from "../../src/lib/llm/sse.js";
import { unitDeps } from "../../src/lib/deps.js";
import { transcriptWithTimes } from "../../src/ai/_artifacts.js";
import { chatHandler, generateCalendarEventsHandler, generateChaptersHandler, generateQuizHandler, renameSpeakerHandler, setActionItemDoneHandler } from "../../src/ai/handler.js";
import { chunkLines, summaryAsText, translateHandler, TranslateInput } from "../../src/ai/translation.js";
import { ActionItemsData, CalendarEventsData, ChaptersData, KeyTermsData, MindmapData, QuizData, SpeakersData } from "../../src/ai/types.js";
import { ACTION_ITEMS_PROMPT, CALENDAR_EVENTS_PROMPT, CHAPTERS_PROMPT, CHAT_SYSTEM, KEY_TERMS_PROMPT, MAP_SPEAKERS_PROMPT, QUIZ_PROMPT } from "../../src/prompts/ai.js";
import { fill } from "../../src/prompts/summarize.js";

const client = { appVersion: "2.0.0", build: 1, platform: "ios" as const };
const caller = { uid: "u1", signInProvider: "google.com" };

function stream(lines: string[]): ReadableStream<Uint8Array> {
  const enc = new TextEncoder();
  return new ReadableStream({ start(c) { for (const l of lines) c.enqueue(enc.encode(l)); c.close(); } });
}

describe("sseData", () => {
  it("yields data payloads across chunk boundaries and ignores other lines", async () => {
    const out: string[] = [];
    for await (const d of sseData(stream(["event: x\ndata: {\"a\":1}\n\nda", "ta: [DONE]\n"]))) out.push(d);
    expect(out).toEqual(['{"a":1}', "[DONE]"]);
  });
});

describe("openAiClient.streamText", () => {
  it("emits deltas in order, returns the full text and usage", async () => {
    const ev = (o: unknown) => `data: ${JSON.stringify(o)}\n`;
    const body = [
      ev({ model: "gpt-x", choices: [{ delta: { content: "Hel" } }] }),
      ev({ choices: [{ delta: { content: "lo" } }] }),
      ev({ choices: [{ delta: {} }], usage: { prompt_tokens: 7, completion_tokens: 2 } }),
      "data: [DONE]\n",
    ];
    const fetchImpl: typeof fetch = async () => new Response(stream(body), { status: 200 });
    const deltas: string[] = [];
    const out = await openAiClient({ apiKey: "k", model: "m", timeoutMs: 5000, fetchImpl }).streamText({ name: "t", prompt: "p", maxOutputTokens: 10 }, (d) => deltas.push(d));
    expect(deltas).toEqual(["Hel", "lo"]);
    expect(out).toEqual({ text: "Hello", model: "gpt-x", tokens: { input: 7, output: 2 } });
  });
  it("an empty stream is unavailable", async () => {
    const fetchImpl: typeof fetch = async () => new Response(stream(["data: [DONE]\n"]), { status: 200 });
    await expect(openAiClient({ apiKey: "k", model: "m", timeoutMs: 5000, fetchImpl }).streamText({ name: "t", prompt: "p", maxOutputTokens: 10 }, () => undefined)).rejects.toMatchObject({ code: "unavailable" });
  });
  it("passes history as prior messages", async () => {
    let body: { messages: { role: string; content: string }[] } | undefined;
    const fetchImpl: typeof fetch = async (_u, init) => { body = JSON.parse(String(init?.body)); return new Response(stream(['data: {"choices":[{"delta":{"content":"ok"}}]}\n', "data: [DONE]\n"]), { status: 200 }); };
    await openAiClient({ apiKey: "k", model: "m", timeoutMs: 5000, fetchImpl }).streamText({ name: "t", system: "s", history: [{ role: "user", text: "a" }, { role: "assistant", text: "b" }], prompt: "c", maxOutputTokens: 10 }, () => undefined);
    expect(body?.messages.map((m) => m.role)).toEqual(["system", "user", "assistant", "user"]);
  });
});

describe("geminiClient.streamText", () => {
  it("emits deltas and maps assistant→model in history", async () => {
    let body: { contents: { role: string }[] } | undefined;
    const ev = (o: unknown) => `data: ${JSON.stringify(o)}\n`;
    const fetchImpl: typeof fetch = async (_u, init) => {
      body = JSON.parse(String(init?.body));
      return new Response(stream([ev({ candidates: [{ content: { parts: [{ text: "Hi" }] } }] }), ev({ candidates: [{ content: { parts: [{ text: "!" }] } }], usageMetadata: { promptTokenCount: 1, candidatesTokenCount: 1 } })]), { status: 200 });
    };
    const deltas: string[] = [];
    const out = await geminiClient({ apiKey: "k", model: "g", timeoutMs: 5000, fetchImpl }).streamText({ name: "t", history: [{ role: "assistant", text: "x" }], prompt: "p", maxOutputTokens: 10 }, (d) => deltas.push(d));
    expect(out.text).toBe("Hi!");
    expect(deltas).toEqual(["Hi", "!"]);
    expect(body?.contents.map((c) => c.role)).toEqual(["model", "user"]);
  });
});

describe("schemas", () => {
  it("QuizData rejects an answerIndex outside the options", () => {
    expect(QuizData.safeParse({ items: [{ question: "q", options: ["a", "b"], answerIndex: 2 }] }).success).toBe(false);
    expect(QuizData.safeParse({ items: [{ question: "q", options: ["a", "b"], answerIndex: 1 }] }).success).toBe(true);
  });
  it("MindmapData is depth-limited and fills missing children with []", () => {
    const p = MindmapData.parse({ root: { id: "r", title: "T", icon: "🎯", children: [{ id: "n1", title: "A" }] } });
    expect(p.root.children[0]?.children).toEqual([]);
    expect(MindmapData.safeParse({ root: { id: "r", title: "T", icon: "🎯", children: [] } }).success).toBe(false);
  });
  it("CalendarEventsData accepts an empty list and caps at 20", () => {
    expect(CalendarEventsData.safeParse({ events: [] }).success).toBe(true);
    const ev = { id: "e1", title: "t", description: "d", datetime: "2026-09-25T10:00:00+07:00", participants: [], rawText: "r" };
    expect(CalendarEventsData.safeParse({ events: Array.from({ length: 21 }, () => ev) }).success).toBe(false);
  });
  it("ActionItemsData allows null owner/due and an empty decisions list; ChaptersData rejects end < start", () => {
    expect(ActionItemsData.safeParse({ items: [{ id: "a1", text: "Send deck", owner: null, due: null, quote: "send the deck" }], decisions: [] }).success).toBe(true);
    expect(ActionItemsData.safeParse({ items: [{ id: "a1", text: "", owner: null, due: null, quote: "" }], decisions: [] }).success).toBe(false);
    expect(KeyTermsData.safeParse({ terms: [{ term: "TCA", definition: "d", quote: "" }] }).success).toBe(true);
    expect(ChaptersData.safeParse({ chapters: [{ title: "t", startSeconds: 5, endSeconds: 2, summary: "" }] }).success).toBe(false);
    expect(ChaptersData.safeParse({ chapters: [] }).success).toBe(false);
  });
  it("SpeakersData only accepts speaker_N ids", () => {
    expect(SpeakersData.safeParse({ speakers: [{ id: "bob", label: "Bob" }] }).success).toBe(false);
    expect(SpeakersData.safeParse({ speakers: [{ id: "speaker_2", label: "Bob" }] }).success).toBe(true);
  });
});

describe("prompts", () => {
  it("every template fills without a leftover placeholder", () => {
    expect(fill(QUIZ_PROMPT, { transcript: "t", languageCode: "vi" })).not.toContain("{{");
    expect(fill(MAP_SPEAKERS_PROMPT, { speakerIds: "speaker_0", transcript: "t" })).not.toContain("{{");
    expect(fill(CHAT_SYSTEM, { languageCode: "en" })).toContain("'en'");
    const cal = fill(CALENDAR_EVENTS_PROMPT, { transcript: "t", languageCode: "vi", now: "2026-09-23T10:00:00.000Z", timezone: "Asia/Ho_Chi_Minh" });
    expect(cal).not.toContain("{{");
    expect(cal).toContain("Asia/Ho_Chi_Minh");
    expect(fill(ACTION_ITEMS_PROMPT, { transcript: "t", languageCode: "en", now: "n", timezone: "UTC" })).not.toContain("{{");
    expect(fill(KEY_TERMS_PROMPT, { transcript: "t", languageCode: "en" })).not.toContain("{{");
    expect(fill(CHAPTERS_PROMPT, { transcript: "t", languageCode: "en" })).not.toContain("{{");
  });
  it("transcriptWithTimes renders one timestamped line per segment", () => {
    const t = { durationSeconds: 5, languageCode: null, languageProbability: null, text: "a b", segments: [
      { startSeconds: 0, endSeconds: 1.25, text: "a", speakerId: "speaker_0", speakerLabel: "S1" },
      { startSeconds: 1.25, endSeconds: 5, text: "b", speakerId: "speaker_1", speakerLabel: "S2" },
    ] };
    expect(transcriptWithTimes(t)).toBe("[0.0-1.3] speaker_0: a\n[1.3-5.0] speaker_1: b");
  });
});

describe("handlers — validation", () => {
  const deps = unitDeps();
  it("chat: question over 2000 chars is invalid-argument", async () => {
    await expect(chatHandler(caller, { client, minuteId: "m1", question: "x".repeat(2001) }, deps)).rejects.toMatchObject({ code: "invalid-argument" });
  });
  it("generateQuiz: languageCode defaults to en; unknown keys rejected", async () => {
    await expect(generateQuizHandler(caller, { client, minuteId: "m1", summaryText: "x" }, deps)).rejects.toMatchObject({ code: "invalid-argument" });
  });
  it("generateCalendarEvents: timezone must be IANA when given", async () => {
    await expect(generateCalendarEventsHandler(caller, { client, minuteId: "m1", timezone: "GMT+7" }, deps)).rejects.toMatchObject({ code: "invalid-argument" });
  });
  it("generateChapters: unknown keys rejected like every generator", async () => {
    await expect(generateChaptersHandler(caller, { client, minuteId: "m1", timezone: "UTC" }, deps)).rejects.toMatchObject({ code: "invalid-argument" });
  });
  it("renameSpeaker: speakerId must be speaker_N (v1 accepted any string as a Firestore field name)", async () => {
    await expect(renameSpeakerHandler(caller, { client, minuteId: "m1", speakerId: "__proto__", name: "x" }, deps)).rejects.toMatchObject({ code: "invalid-argument" });
  });
});

describe("setActionItemDone", () => {
  const deps = unitDeps();
  it("requires auth", async () => {
    await expect(setActionItemDoneHandler(undefined, { client, minuteId: "m1", itemId: "a1", done: true }, deps)).rejects.toMatchObject({ code: "unauthenticated" });
  });
  it("validates itemId and done", async () => {
    await expect(setActionItemDoneHandler(caller, { client, minuteId: "m1", itemId: "", done: true }, deps)).rejects.toMatchObject({ code: "invalid-argument" });
    await expect(setActionItemDoneHandler(caller, { client, minuteId: "m1", itemId: "a1", done: "yes" }, deps)).rejects.toMatchObject({ code: "invalid-argument" });
    await expect(setActionItemDoneHandler(caller, { client, minuteId: "m1", itemId: "a1" }, deps)).rejects.toMatchObject({ code: "invalid-argument" });
  });
  it("ActionItemsData defaults done to false so model output never needs it", () => {
    const parsed = ActionItemsData.parse({ items: [{ id: "a1", text: "t", owner: null, due: null, quote: "q" }], decisions: [] });
    expect(parsed.items[0]?.done).toBe(false);
  });
});

describe("translate (S11-04)", () => {
  it("input: part is summary|transcript, languageCode required", () => {
    expect(TranslateInput.parse({ client, minuteId: "m1", part: "summary", languageCode: "vi" }).force).toBe(false);
    expect(() => TranslateInput.parse({ client, minuteId: "m1", part: "notes", languageCode: "vi" })).toThrow();
    expect(() => TranslateInput.parse({ client, minuteId: "m1", part: "summary" })).toThrow();
  });
  it("requires auth before touching anything", async () => {
    await expect(translateHandler(undefined, { client, minuteId: "m1", part: "summary", languageCode: "vi" }, unitDeps())).rejects.toMatchObject({ code: "unauthenticated" });
  });
  it("summaryAsText keeps headings and bullets on their own lines", () => {
    const t = summaryAsText({ title: "T", text: "Body", icon: null, sections: [{ title: "A", bullets: ["• x", "    ◦ y"] }] });
    expect(t.split("\n")).toEqual(["# T", "", "Body", "", "## A", "• x", "    ◦ y"]);
  });
  it("chunkLines splits on line boundaries under the cap and never drops text", () => {
    const lines = Array.from({ length: 50 }, (_, i) => `speaker_${i % 2}: ${"word ".repeat(40)}${i}`);
    const chunks = chunkLines(lines.join("\n"), 2000);
    expect(chunks.length).toBeGreaterThan(1);
    for (const c of chunks) expect(c.length).toBeLessThanOrEqual(2000);
    expect(chunks.join("\n")).toBe(lines.join("\n"));
    expect(chunkLines("x".repeat(10), 3)).toEqual(["x".repeat(10)]); // one over-long line stays whole
  });
});

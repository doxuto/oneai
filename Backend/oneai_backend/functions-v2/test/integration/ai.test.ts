/** Runs under `npm run test:integration`. */
import { getStorage } from "firebase-admin/storage";
import { Timestamp } from "firebase-admin/firestore";
import { beforeEach, describe, expect, it } from "vitest";
import { HttpsError } from "firebase-functions/v2/https";
import { chatHandler, generateActionItemsHandler, generateCalendarEventsHandler, generateChaptersHandler, generateFlashcardsHandler, generateKeyTermsHandler, generateMindmapHandler, generateQuizHandler, generateShortQuestionsHandler, listChatMessagesHandler, mapSpeakersHandler, renameSpeakerHandler, setActionItemDoneHandler } from "../../src/ai/handler.js";
import { unitDeps, type Deps } from "../../src/lib/deps.js";
import type { LlmClient } from "../../src/lib/llm/types.js";
import { clearFirestore, fixedNow, testDb } from "../helpers/emulator.js";

const db = testDb();
const bucket = getStorage().bucket("demo-oneai.appspot.com");
const client = { appVersion: "2.0.0", build: 1, platform: "ios" as const };
const u1 = { uid: "u1", signInProvider: "google.com" };

const transcript = {
  durationSeconds: 10, languageCode: "eng", languageProbability: 0.9, text: "Hi, I'm Ana. Sure, thanks Ana.",
  segments: [
    { startSeconds: 0, endSeconds: 4, text: "Hi, I'm Ana.", speakerId: "speaker_0", speakerLabel: "Speaker 1" },
    { startSeconds: 5, endSeconds: 10, text: "Sure, thanks Ana.", speakerId: "speaker_1", speakerLabel: "Speaker 2" },
  ],
};

function fakeLlm(json: () => Promise<unknown>, textDeltas: string[] = ["An", "swer"]): LlmClient & { calls: number } {
  const c = {
    vendor: "openai" as const, calls: 0,
    async generateJson() { c.calls++; return { data: (await json()) as never, model: "fake", tokens: { input: 1, output: 1 } }; },
    async streamText(_req: unknown, onDelta: (d: string) => void) { c.calls++; for (const d of textDeltas) onDelta(d); return { text: textDeltas.join(""), model: "fake", tokens: { input: 2, output: 2 } }; },
  };
  return c;
}
function makeDeps(llm: LlmClient): Deps {
  return unitDeps({ db, bucket: bucket as Deps["bucket"], now: fixedNow(), services: { llm } });
}
async function seedReady(id = "m1", t: unknown = transcript) {
  await bucket.file(`users/u1/minutes/${id}/transcript.json`).save(JSON.stringify(t), { resumable: false });
  await db.doc(`users/u1/minutes/${id}`).set({ title: "a", status: "ready", sourceType: "audio", transcriptPath: `users/u1/minutes/${id}/transcript.json`, tagIds: [], createdAt: Timestamp.now(), updatedAt: Timestamp.now() });
}

describe("generate* with artifact cache", () => {
  beforeEach(async () => { await clearFirestore(); const [f] = await bucket.getFiles({ prefix: "users/" }); await Promise.all(f.map((x) => x.delete())); });

  it("first call generates and stores; second call is served from cache without the model", async () => {
    await seedReady();
    const llm = fakeLlm(async () => ({ questions: ["Who is Ana?"] }));
    const deps = makeDeps(llm);
    const a = await generateShortQuestionsHandler(u1, { client, minuteId: "m1" }, deps);
    expect(a).toEqual({ data: { questions: ["Who is Ana?"] }, cached: false });
    const b = await generateShortQuestionsHandler(u1, { client, minuteId: "m1" }, deps);
    expect(b.cached).toBe(true);
    expect(llm.calls).toBe(1);
    expect((await db.doc("users/u1/minutes/m1/artifacts/shortQuestions").get()).data()).toMatchObject({ kind: "shortQuestions", model: "fake" });
  });

  it("a changed transcript invalidates the cache", async () => {
    await seedReady();
    const llm = fakeLlm(async () => ({ questions: ["q"] }));
    const deps = makeDeps(llm);
    await generateShortQuestionsHandler(u1, { client, minuteId: "m1" }, deps);
    await seedReady("m1", { ...transcript, text: "different" });
    const b = await generateShortQuestionsHandler(u1, { client, minuteId: "m1" }, deps);
    expect(b.cached).toBe(false);
    expect(llm.calls).toBe(2);
  });

  it("force:true regenerates", async () => {
    await seedReady();
    const llm = fakeLlm(async () => ({ questions: ["q"] }));
    const deps = makeDeps(llm);
    await generateShortQuestionsHandler(u1, { client, minuteId: "m1" }, deps);
    await generateShortQuestionsHandler(u1, { client, minuteId: "m1", force: true }, deps);
    expect(llm.calls).toBe(2);
  });

  it("a failed generation writes nothing, so the next call tries again", async () => {
    await seedReady();
    let n = 0;
    const llm = fakeLlm(async () => { if (n++ === 0) throw new HttpsError("unavailable", "bad shape"); return { items: [{ question: "q", options: ["a", "b"], answerIndex: 0 }] }; });
    const deps = makeDeps(llm);
    await expect(generateQuizHandler(u1, { client, minuteId: "m1" }, deps)).rejects.toMatchObject({ code: "unavailable" });
    expect((await db.doc("users/u1/minutes/m1/artifacts/quiz").get()).exists).toBe(false);
    const ok = await generateQuizHandler(u1, { client, minuteId: "m1" }, deps);
    expect(ok.cached).toBe(false);
    expect(ok.data.items[0]?.answerIndex).toBe(0);
  });

  it("flashcards and mindmap each live in their own artifact doc and cache independently", async () => {
    await seedReady();
    const llm = fakeLlm(async () => ({ items: [{ question: "Who?", answer: "Ana" }] }));
    const cards = await generateFlashcardsHandler(u1, { client, minuteId: "m1", languageCode: "vi" }, makeDeps(llm));
    expect(cards).toEqual({ data: { items: [{ question: "Who?", answer: "Ana" }] }, cached: false });

    const mm = fakeLlm(async () => ({ root: { id: "r", title: "Intro", icon: "🎯", children: [{ id: "n1", title: "Ana" }] } }));
    const map = await generateMindmapHandler(u1, { client, minuteId: "m1" }, makeDeps(mm));
    expect(map.cached).toBe(false);
    expect(map.data.root.children[0]).toMatchObject({ id: "n1", title: "Ana" }); // the fake LLM returns its JSON verbatim; schema defaults are the adapter's job (unit-tested)

    // Each kind has its own cache: a second flashcards call hits, mindmap untouched.
    expect((await generateFlashcardsHandler(u1, { client, minuteId: "m1" }, makeDeps(llm))).cached).toBe(true);
    expect(llm.calls).toBe(1);
    expect(mm.calls).toBe(1);
    const ids = (await db.collection("users/u1/minutes/m1/artifacts").get()).docs.map((d) => d.id).sort();
    expect(ids).toEqual(["flashcards", "mindmap"]);
  });

  it("refuses a note that is not ready", async () => {
    await db.doc("users/u1/minutes/m1").set({ status: "transcribing", createdAt: Timestamp.now() });
    await expect(generateQuizHandler(u1, { client, minuteId: "m1" }, makeDeps(fakeLlm(async () => ({}))))).rejects.toMatchObject({ code: "failed-precondition", details: { reason: "notReady" } });
  });
});

describe("calendarEvents", () => {
  beforeEach(async () => { await clearFirestore(); const [f] = await bucket.getFiles({ prefix: "users/" }); await Promise.all(f.map((x) => x.delete())); });

  it("uses the minute's stored timezone, then overwrites the ingest-time artifact with a hashed one", async () => {
    await seedReady();
    await db.doc("users/u1/minutes/m1").update({ timezone: "Asia/Ho_Chi_Minh" });
    // As the pipeline writes it: no sourceHash.
    await db.doc("users/u1/minutes/m1/artifacts/calendarEvents").set({ kind: "calendarEvents", data: { events: [] }, model: "fake" });
    let seenPrompt = "";
    const llm = fakeLlm(async () => ({ events: [{ id: "e1", title: "Retro", description: "d", datetime: "2026-09-25T10:00:00+07:00", participants: [], rawText: "r" }] }));
    const spy: LlmClient = { ...llm, async generateJson(req) { seenPrompt = req.prompt; return llm.generateJson(req); } };
    const deps = makeDeps(spy);

    const a = await generateCalendarEventsHandler(u1, { client, minuteId: "m1" }, deps);
    expect(a.cached).toBe(false);
    expect(a.data.events[0]?.title).toBe("Retro");
    expect(seenPrompt).toContain("Asia/Ho_Chi_Minh");
    expect((await db.doc("users/u1/minutes/m1/artifacts/calendarEvents").get()).data()).toMatchObject({ kind: "calendarEvents", sourceHash: expect.any(String) });

    const b = await generateCalendarEventsHandler(u1, { client, minuteId: "m1" }, deps);
    expect(b.cached).toBe(true);
    expect(llm.calls).toBe(1);
  });

  it("an explicit timezone wins over the stored one", async () => {
    await seedReady();
    let seenPrompt = "";
    const llm = fakeLlm(async () => ({ events: [] }));
    const spy: LlmClient = { ...llm, async generateJson(req) { seenPrompt = req.prompt; return llm.generateJson(req); } };
    await generateCalendarEventsHandler(u1, { client, minuteId: "m1", timezone: "Europe/Berlin" }, makeDeps(spy));
    expect(seenPrompt).toContain("Europe/Berlin");
  });
});

describe("actionItems / keyTerms / chapters", () => {
  beforeEach(async () => { await clearFirestore(); const [f] = await bucket.getFiles({ prefix: "users/" }); await Promise.all(f.map((x) => x.delete())); });

  it("action items use the stored timezone and cache under their own kind", async () => {
    await seedReady();
    await db.doc("users/u1/minutes/m1").update({ timezone: "Asia/Ho_Chi_Minh" });
    let seen = "";
    const llm = fakeLlm(async () => ({ items: [{ id: "a1", text: "Thank Ana", owner: "speaker_1", due: null, quote: "thanks Ana" }], decisions: ["Ana leads"] }));
    const spy: LlmClient = { ...llm, async generateJson(req) { seen = req.prompt; return llm.generateJson(req); } };
    const out = await generateActionItemsHandler(u1, { client, minuteId: "m1", languageCode: "vi" }, makeDeps(spy));
    expect(out.data.items[0]?.text).toBe("Thank Ana");
    expect(out.data.decisions).toEqual(["Ana leads"]);
    expect(seen).toContain("Asia/Ho_Chi_Minh");
    expect(seen).toContain("'vi'");
    expect((await db.doc("users/u1/minutes/m1/artifacts/actionItems").get()).exists).toBe(true);
    expect((await generateActionItemsHandler(u1, { client, minuteId: "m1", languageCode: "vi" }, makeDeps(spy))).cached).toBe(true);
    expect(llm.calls).toBe(1);
  });

  it("setActionItemDone ticks one item inside the artifact, is idempotent, and needs no model", async () => {
    await seedReady();
    const llm = fakeLlm(async () => ({ items: [
      { id: "a1", text: "Thank Ana", owner: null, due: null, quote: "q" },
      { id: "a2", text: "Send notes", owner: null, due: null, quote: "q" },
    ], decisions: [] }));
    const deps = makeDeps(llm);
    await generateActionItemsHandler(u1, { client, minuteId: "m1" }, deps);
    const out = await setActionItemDoneHandler(u1, { client, minuteId: "m1", itemId: "a2", done: true }, deps);
    expect(out.data.items.map((i) => [i.id, i.done])).toEqual([["a1", false], ["a2", true]]);
    // Reading again (cached) shows the tick; untick works; the model was called once.
    const again = await generateActionItemsHandler(u1, { client, minuteId: "m1" }, deps);
    expect(again.cached).toBe(true);
    expect(again.data.items[1]?.done).toBe(true);
    const off = await setActionItemDoneHandler(u1, { client, minuteId: "m1", itemId: "a2", done: false }, deps);
    expect(off.data.items[1]?.done).toBe(false);
    expect(llm.calls).toBe(1);
  });

  it("setActionItemDone refuses before generation and for an unknown item", async () => {
    await seedReady();
    const deps = makeDeps(fakeLlm(async () => ({ items: [{ id: "a1", text: "t", owner: null, due: null, quote: "q" }], decisions: [] })));
    await expect(setActionItemDoneHandler(u1, { client, minuteId: "m1", itemId: "a1", done: true }, deps)).rejects.toMatchObject({ code: "failed-precondition", details: { reason: "noActionItems" } });
    await generateActionItemsHandler(u1, { client, minuteId: "m1" }, deps);
    await expect(setActionItemDoneHandler(u1, { client, minuteId: "m1", itemId: "zz", done: true }, deps)).rejects.toMatchObject({ code: "not-found" });
    await expect(setActionItemDoneHandler({ uid: "u2", signInProvider: "google.com" }, { client, minuteId: "m1", itemId: "a1", done: true }, deps)).rejects.toMatchObject({ code: "not-found" });
  });

  it("key terms go through the shared generator", async () => {
    await seedReady();
    const llm = fakeLlm(async () => ({ terms: [{ term: "Ana", definition: "A person", quote: "I'm Ana" }] }));
    const out = await generateKeyTermsHandler(u1, { client, minuteId: "m1" }, makeDeps(llm));
    expect(out).toEqual({ data: { terms: [{ term: "Ana", definition: "A person", quote: "I'm Ana" }] }, cached: false });
  });

  it("chapters get a timestamped transcript and are clamped to the recording; a PDF is refused", async () => {
    await seedReady();
    let seen = "";
    const llm = fakeLlm(async () => ({ chapters: [{ title: "Intro", startSeconds: -1, endSeconds: 4, summary: "hi" }, { title: "Reply", startSeconds: 5, endSeconds: 99, summary: "" }] }));
    const spy: LlmClient = { ...llm, async generateJson(req) { seen = req.prompt; return llm.generateJson(req); } };
    const out = await generateChaptersHandler(u1, { client, minuteId: "m1" }, makeDeps(spy));
    expect(seen).toContain("[0.0-4.0] speaker_0: Hi, I'm Ana.");
    expect(out.data.chapters).toEqual([
      { title: "Intro", startSeconds: 0, endSeconds: 4, summary: "hi" },
      { title: "Reply", startSeconds: 5, endSeconds: 10, summary: "" },
    ]);

    await seedReady("pdf", { durationSeconds: 0, languageCode: null, languageProbability: null, text: "doc", segments: [{ startSeconds: 0, endSeconds: 0, text: "doc", speakerId: "document", speakerLabel: "Document" }] });
    await expect(generateChaptersHandler(u1, { client, minuteId: "pdf" }, makeDeps(spy))).rejects.toMatchObject({ code: "failed-precondition", details: { reason: "noTimeline" } });
  });
});

describe("speakers", () => {
  beforeEach(async () => { await clearFirestore(); const [f] = await bucket.getFiles({ prefix: "users/" }); await Promise.all(f.map((x) => x.delete())); });

  it("mapSpeakers returns every id exactly once, filling gaps the model left", async () => {
    await seedReady();
    const llm = fakeLlm(async () => ({ speakers: [{ id: "speaker_0", label: "Ana" }] })); // model forgot speaker_1
    const out = await mapSpeakersHandler(u1, { client, minuteId: "m1" }, makeDeps(llm));
    expect(out.data.speakers).toEqual([{ id: "speaker_0", label: "Ana" }, { id: "speaker_1", label: "speaker_1" }]);
    expect((await db.doc("users/u1/minutes/m1/artifacts/speakers").get()).data()?.data.speakers).toHaveLength(2);
  });

  it("a single-speaker note needs no model call", async () => {
    await seedReady("m1", { ...transcript, segments: [transcript.segments[0]] });
    const llm = fakeLlm(async () => ({}));
    const out = await mapSpeakersHandler(u1, { client, minuteId: "m1" }, makeDeps(llm));
    expect(out.data.speakers).toEqual([{ id: "speaker_0", label: "Speaker 1" }]);
    expect(llm.calls).toBe(0);
  });

  it("renameSpeaker updates without the model and survives when no artifact exists yet", async () => {
    await seedReady();
    const llm = fakeLlm(async () => ({}));
    const deps = makeDeps(llm);
    const out = await renameSpeakerHandler(u1, { client, minuteId: "m1", speakerId: "speaker_1", name: "  Bob " }, deps);
    expect(out.data.speakers).toEqual([{ id: "speaker_1", label: "Bob" }]);
    expect(llm.calls).toBe(0);
  });
});

describe("chat", () => {
  beforeEach(async () => { await clearFirestore(); const [f] = await bucket.getFiles({ prefix: "users/" }); await Promise.all(f.map((x) => x.delete())); });

  it("streams deltas, persists both turns, and lists them in order with a cursor", async () => {
    await seedReady();
    const deps = makeDeps(fakeLlm(async () => ({}), ["An", "swer"]));
    const deltas: string[] = [];
    const out = await chatHandler(u1, { client, minuteId: "m1", question: "Who spoke?" }, deps, (d) => deltas.push(d));
    expect(deltas).toEqual(["An", "swer"]);
    expect(out.answer).toBe("Answer");

    const list = await listChatMessagesHandler(u1, { client, minuteId: "m1", limit: 1 }, deps);
    expect(list.items.map((m) => m.role)).toEqual(["user"]);
    expect(list.nextCursor).not.toBeNull();
    const rest = await listChatMessagesHandler(u1, { client, minuteId: "m1", limit: 1, cursor: list.nextCursor! }, deps);
    expect(rest.items.map((m) => [m.role, m.text])).toEqual([["assistant", "Answer"]]);
    expect(rest.nextCursor).toBeNull();
  });

  it("feeds prior turns back as history", async () => {
    await seedReady();
    let seenHistory: unknown;
    const llm: LlmClient = { vendor: "openai", generateJson: async () => { throw new Error("unused"); },
      async streamText(req, onDelta) { seenHistory = req.history; onDelta("ok"); return { text: "ok", model: "f", tokens: { input: 0, output: 0 } }; } };
    const deps = makeDeps(llm);
    await chatHandler(u1, { client, minuteId: "m1", question: "first" }, deps);
    await chatHandler(u1, { client, minuteId: "m1", question: "second" }, deps);
    expect(seenHistory).toEqual([{ role: "user", text: "first" }, { role: "assistant", text: "ok" }]);
  });

  it("chat on another user's note is not-found", async () => {
    await seedReady();
    await expect(chatHandler({ uid: "u2", signInProvider: "x" }, { client, minuteId: "m1", question: "?" }, makeDeps(fakeLlm(async () => ({}))))).rejects.toMatchObject({ code: "not-found" });
  });
});

describe("AI daily cap (unitDeps: free = 3 calls/day)", () => {
  beforeEach(async () => { await clearFirestore(); const [f] = await bucket.getFiles({ prefix: "users/" }); await Promise.all(f.map((x) => x.delete())); await db.doc("users/u1").set({ plan: "free" }); });

  it("the 4th model call today is resource-exhausted with reason:aiDailyLimit; cache hits do not count", async () => {
    await seedReady();
    const llm = fakeLlm(async () => ({ questions: ["q"] }));
    const deps = makeDeps(llm);
    await chatHandler(u1, { client, minuteId: "m1", question: "1" }, deps);
    await chatHandler(u1, { client, minuteId: "m1", question: "2" }, deps);
    await generateShortQuestionsHandler(u1, { client, minuteId: "m1" }, deps);            // 3rd call
    await generateShortQuestionsHandler(u1, { client, minuteId: "m1" }, deps);            // cached → free
    await expect(chatHandler(u1, { client, minuteId: "m1", question: "4" }, deps)).rejects.toMatchObject({
      code: "resource-exhausted", details: { reason: "aiDailyLimit", limit: 3, used: 3 },
    });
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.aiCalls).toBe(3);
    expect(llm.calls).toBe(3);
  });

  it("premium has its own, larger cap", async () => {
    await db.doc("users/u1").set({ plan: "premium", planExpiresAt: null });
    await seedReady();
    const deps = makeDeps(fakeLlm(async () => ({})));
    for (let i = 0; i < 5; i++) await chatHandler(u1, { client, minuteId: "m1", question: `${i}` }, deps);
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.aiCalls).toBe(5);
  });
});

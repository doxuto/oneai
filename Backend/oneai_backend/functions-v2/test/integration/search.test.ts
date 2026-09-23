import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { beforeEach, describe, expect, it } from "vitest";
import { unitDeps, type Deps } from "../../src/lib/deps.js";
import type { Embedder } from "../../src/lib/llm/embeddings.js";
import type { LlmClient } from "../../src/lib/llm/types.js";
import { embedMinute } from "../../src/search/embedding.js";
import { askAllHandler, searchNotesHandler } from "../../src/search/handler.js";
import { backfill } from "../../src/jobs/backfillEmbeddings.js";
import { clearFirestore, fixedNow, testDb } from "../helpers/emulator.js";

const db = testDb();
const bucket = getStorage().bucket("demo-oneai.appspot.com");
const client = { appVersion: "2.0.0", build: 1, platform: "ios" as const };
const u1 = { uid: "u1", signInProvider: "google.com" };

/** Toy 3-d space: "ship" notes near [1,0,0], "hiring" near [0,1,0]; a query is the axis its first word names. */
function fakeEmbedder(): Embedder & { calls: number } {
  const vec = (t: string): number[] => (/ship|release|friday/i.test(t) ? [1, 0, 0] : /hir|interview|candidate/i.test(t) ? [0, 1, 0] : [0, 0, 1]);
  const e = { vendor: "openai" as const, dimension: 3, calls: 0, async embed(texts: string[]) { e.calls++; return texts.map(vec); } };
  return e;
}
function fakeLlm(reply: string): LlmClient & { lastSystem?: string; lastHistory?: unknown } {
  const c: LlmClient & { lastSystem?: string; lastHistory?: unknown } = {
    vendor: "openai",
    async generateJson() { throw new Error("not used"); },
    async streamText(req, onDelta) { c.lastSystem = req.system; c.lastHistory = req.history; onDelta(reply); return { text: reply, model: "fake", tokens: { input: 1, output: 1 } }; },
  };
  return c;
}
function makeDeps(llm: LlmClient, embedder: Embedder): Deps {
  return unitDeps({ db, bucket: bucket as Deps["bucket"], now: fixedNow(), services: { llm, embedder } });
}
const summary = (text: string) => ({ title: "S", text, icon: null, sections: [] });
async function seed(id: string, title: string, text: string, status = "ready") {
  await db.doc(`users/u1/minutes/${id}`).set({ title, status, sourceType: "audio", summary: summary(text), tagIds: [], createdAt: Timestamp.fromDate(new Date("2026-09-18T09:00:00Z")), updatedAt: Timestamp.now() });
}

describe("S11-01/02 — embeddings, semantic search, ask across notes", () => {
  beforeEach(async () => { await clearFirestore(); await db.doc("users/u1").set({ plan: "free" }); });

  it("embedMinute stores a vector + hash once; unchanged doc is skipped; changed summary re-embeds", async () => {
    const emb = fakeEmbedder();
    const deps = makeDeps(fakeLlm(""), emb);
    await seed("m1", "Release plan", "We ship Friday.");
    expect(await embedMinute(deps, "u1", "m1")).toBe("stored");
    expect(await embedMinute(deps, "u1", "m1")).toBe("skipped");
    expect(emb.calls).toBe(1);
    const d = (await db.doc("users/u1/minutes/m1").get()).data()!;
    expect(d.embeddingHash).toMatch(/^[0-9a-f]{40}$/);
    expect(d.embedding).toBeDefined();
    await db.doc("users/u1/minutes/m1").update({ summary: summary("Now about hiring a candidate.") });
    expect(await embedMinute(deps, "u1", "m1")).toBe("stored");
    expect(emb.calls).toBe(2);
    await seed("m2", "Draft", "x", "processing");
    expect(await embedMinute(deps, "u1", "m2")).toBe("skipped");
  });

  it("searchNotes ranks by vector distance, only the caller's ready notes", async () => {
    const deps = makeDeps(fakeLlm(""), fakeEmbedder());
    await seed("ship", "Release plan", "We ship Friday.");
    await seed("hire", "Interview", "Candidate was strong.");
    await seed("other", "Lunch", "Pho or bun cha.");
    await db.doc("users/u2/minutes/theirs").set({ title: "Ship", status: "ready", summary: summary("ship"), createdAt: Timestamp.now(), embedding: FieldValue.vector([1, 0, 0]), embeddingHash: "x" });
    for (const id of ["ship", "hire", "other"]) await embedMinute(deps, "u1", id);
    const { items } = await searchNotesHandler(u1, { client, query: "when do we ship?" }, deps);
    expect(items[0]).toMatchObject({ minuteId: "ship", title: "Release plan" });
    expect(items.map((i) => i.minuteId)).not.toContain("theirs");
    expect(items.map((i) => i.minuteId)).not.toContain("other"); // distance 1.0 > SEARCH_MAX_DISTANCE
    expect(items[0]!.score).toBeCloseTo(1, 3);
  });

  it("askAll puts the nearest notes in the prompt, streams, returns only the cited sources, charges one AI call", async () => {
    const llm = fakeLlm("Friday [[note:ship]].");
    const deps = makeDeps(llm, fakeEmbedder());
    await seed("ship", "Release plan", "We ship Friday.");
    await seed("hire", "Interview", "Candidate was strong.");
    for (const id of ["ship", "hire"]) await embedMinute(deps, "u1", id);
    const deltas: string[] = [];
    const out = await askAllHandler(u1, { client, question: "When is the release?", languageCode: "vi", history: [{ role: "user", text: "hi" }, { role: "assistant", text: "hello" }] }, deps, (d) => deltas.push(d));
    expect(deltas.join("")).toBe("Friday [[note:ship]].");
    expect(out.sources).toEqual([{ minuteId: "ship", title: "Release plan", iconEmoji: null, createdAt: "2026-09-18T09:00:00.000Z" }]);
    expect(llm.lastSystem).toContain("### [[note:ship]] Release plan (2026-09-18)");
    expect(llm.lastSystem).toContain("language code 'vi'");
    expect(llm.lastHistory).toHaveLength(2);
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.aiCalls).toBe(1);
  });

  it("askAll with no embedded notes still answers (empty context) instead of failing", async () => {
    const llm = fakeLlm("I couldn't find that in your notes.");
    const out = await askAllHandler(u1, { client, question: "anything?" }, makeDeps(llm, fakeEmbedder()));
    expect(out.sources).toEqual([]);
    expect(llm.lastSystem).toContain("(no matching notes)");
  });

  it("backfill embeds ready notes without a vector across users and stops at the cap", async () => {
    const emb = fakeEmbedder();
    const deps = makeDeps(fakeLlm(""), emb);
    await seed("a", "A", "ship");
    await seed("b", "B", "hire");
    await db.doc("users/u2/minutes/c").set({ title: "C", status: "ready", summary: summary("ship"), createdAt: Timestamp.now() });
    const r1 = await backfill(deps, 2);
    expect(r1).toMatchObject({ stored: 2, failed: 0 });
    const r2 = await backfill(deps);
    expect(r2.stored).toBe(1);
    expect((await backfill(deps)).stored).toBe(0);
  });

  it("S11-01b: a note with a transcript gets time-stamped chunks; askAll cites the moment and returns startSeconds", async () => {
    const emb = fakeEmbedder();
    const llm = fakeLlm("Friday [[note:ship@45]].");
    const deps = makeDeps(llm, emb);
    await seed("ship", "Release plan", "We ship Friday.");
    const transcript = { durationSeconds: 90, languageCode: "en", languageProbability: 1, text: "…", segments: [
      { startSeconds: 0, endSeconds: 30, text: "Let us talk about hiring a candidate.", speakerId: "speaker_0", speakerLabel: "Ana" },
      { startSeconds: 45, endSeconds: 80, text: "We ship on Friday, release is go.", speakerId: "speaker_1", speakerLabel: "Bob" },
    ] };
    await bucket.file("users/u1/minutes/ship/transcript.json").save(JSON.stringify(transcript), { resumable: false });
    await db.doc("users/u1/minutes/ship").update({ transcriptPath: "users/u1/minutes/ship/transcript.json" });
    expect(await embedMinute(deps, "u1", "ship")).toBe("stored");
    expect(emb.calls).toBe(2); // note + one batch for the chunks
    const chunks = await db.collection("users/u1/minutes/ship/chunks").orderBy("order").get();
    expect(chunks.docs.map((d) => d.data().startSeconds)).toEqual([0, 45]);
    expect((await db.doc("users/u1/minutes/ship").get()).data()?.chunkCount).toBe(2);

    const out = await askAllHandler(u1, { client, question: "when do we ship?" }, deps);
    expect(llm.lastSystem).toContain("[t=45] Bob: We ship on Friday, release is go.");
    expect(llm.lastSystem).not.toContain("[t=0]"); // the hiring chunk is not near the question
    expect(out.sources).toEqual([{ minuteId: "ship", title: "Release plan", iconEmoji: null, createdAt: "2026-09-18T09:00:00.000Z", startSeconds: 45 }]);

    // re-embed after the transcript changes replaces the chunks
    await db.doc("users/u1/minutes/ship").update({ summary: summary("changed") });
    await bucket.file("users/u1/minutes/ship/transcript.json").save(JSON.stringify({ ...transcript, segments: transcript.segments.slice(1) }), { resumable: false });
    expect(await embedMinute(deps, "u1", "ship")).toBe("stored");
    expect((await db.collection("users/u1/minutes/ship/chunks").get()).size).toBe(1);
  });
});


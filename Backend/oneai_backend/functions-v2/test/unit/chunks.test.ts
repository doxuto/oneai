import { describe, expect, it } from "vitest";
import { CHUNK_MAX_PER_NOTE, chunkDocId, chunkTranscript } from "../../src/search/chunks.js";
import { citedSources, noteForPrompt } from "../../src/search/handler.js";

const seg = (i: number, words: number, speaker = "Ana") => ({ startSeconds: i * 10, endSeconds: i * 10 + 9, text: Array.from({ length: words }, (_, k) => `w${i}_${k}`).join(" "), speakerId: `speaker_${i % 2}`, speakerLabel: speaker });

describe("transcript chunks (S11-01b)", () => {
  it("packs consecutive speaker turns up to the word budget, keeps time bounds and labels", () => {
    const t = { durationSeconds: 60, languageCode: "en", languageProbability: 1, text: "x", segments: [seg(0, 100), seg(1, 100), seg(2, 200), seg(3, 50, "Bob")] };
    const chunks = chunkTranscript(t, 250);
    expect(chunks.map((c) => [c.startSeconds, c.endSeconds])).toEqual([[0, 19], [20, 39]]);
    expect(chunks[0]!.text.startsWith("Ana: w0_0")).toBe(true);
    expect(chunks[1]!.text).toContain("\nBob: w3_0");
    expect(chunks.map((c) => c.order)).toEqual([0, 1]);
  });
  it("a single over-long turn is its own chunk; empty turns are skipped", () => {
    const t = { durationSeconds: 30, languageCode: null, languageProbability: null, text: "x", segments: [seg(0, 500), { ...seg(1, 0), text: "   " }, seg(2, 10)] };
    expect(chunkTranscript(t, 100).map((c) => c.startSeconds)).toEqual([0, 20]);
  });
  it("no segments → fixed windows with proportional time stamps; capped per note", () => {
    const t = { durationSeconds: 100, languageCode: null, languageProbability: null, text: Array.from({ length: 1000 }, (_, i) => `w${i}`).join(" "), segments: [] };
    const chunks = chunkTranscript(t, 250);
    expect(chunks).toHaveLength(4);
    expect(chunks[1]).toMatchObject({ startSeconds: 25, endSeconds: 50 });
    const huge = { ...t, segments: Array.from({ length: 1000 }, (_, i) => seg(i, 400)) };
    expect(chunkTranscript(huge).length).toBe(CHUNK_MAX_PER_NOTE);
    expect(chunkDocId(7)).toBe("0007");
  });
});

describe("time-stamped citations", () => {
  const c = [{ minuteId: "a", title: "A", iconEmoji: null, createdAt: null }, { minuteId: "b", title: "B", iconEmoji: null, createdAt: null }];
  it("[[note:id@seconds]] carries startSeconds; a plain citation has none; first citation wins", () => {
    expect(citedSources("x [[note:a@125]] y [[note:b]] z [[note:a@9]]", c)).toEqual([{ ...c[0], startSeconds: 125 }, c[1]]);
  });
  it("noteForPrompt lists matching passages in time order with [t=] marks", () => {
    const p = noteForPrompt("a", { title: "T", summary: { title: "S", text: "sum", icon: null, sections: [] } }, 2500, [
      { minuteId: "a", order: 3, text: "Ana: later\nBob: yes", startSeconds: 300.7, endSeconds: 320, distance: 0.1 },
      { minuteId: "a", order: 1, text: "Ana: early", startSeconds: 40, endSeconds: 60, distance: 0.2 },
    ]);
    expect(p).toContain("Transcript passages:\n[t=40] Ana: early\n[t=300] Ana: later Bob: yes");
  });
});

import { Timestamp } from "firebase-admin/firestore";
import { describe, expect, it } from "vitest";
import { ASK_ALL_NOTE_CHARS, citedSources, noteForPrompt } from "../../src/search/handler.js";
import { embeddingHash, embeddingText, needsEmbedding } from "../../src/search/embedding.js";

const summary = { title: "S", text: "We agreed to ship on Friday.", icon: null, sections: [{ title: "Decisions", bullets: ["Ship Friday", "Ana owns QA"] }] };

describe("embedding text + staleness (S11-01)", () => {
  it("joins title, summary text, sections and the transcript preview", () => {
    const t = embeddingText({ title: "Standup", summary, transcriptPreview: "hello everyone" });
    expect(t.split("\n")).toEqual(["Standup", "We agreed to ship on Friday.", "Decisions", "Ship Friday", "Ana owns QA", "hello everyone"]);
    expect(embeddingText({})).toBe("");
  });

  it("needsEmbedding: ready + text + hash mismatch; the dimension is part of the hash", () => {
    const m = { status: "ready", title: "T", summary };
    expect(needsEmbedding(m, 768)).toBe(true);
    const hash = embeddingHash(embeddingText(m), 768);
    expect(needsEmbedding({ ...m, embeddingHash: hash }, 768)).toBe(false);
    expect(needsEmbedding({ ...m, embeddingHash: hash }, 1536)).toBe(true); // EMBEDDING_DIM changed → re-embed
    expect(needsEmbedding({ ...m, status: "processing" }, 768)).toBe(false);
    expect(needsEmbedding({ status: "ready" }, 768)).toBe(false); // nothing to embed yet
  });
});

describe("ask-all prompt + citations", () => {
  it("noteForPrompt carries the id tag, title, date and clipped body", () => {
    const p = noteForPrompt("m1", { title: "Standup", summary, createdAt: Timestamp.fromDate(new Date("2026-09-20T10:00:00Z")) });
    expect(p).toContain("### [[note:m1]] Standup (2026-09-20)");
    expect(p).toContain("## Decisions\n- Ship Friday\n- Ana owns QA");
    const long = noteForPrompt("m2", { title: "L", summary: { ...summary, text: "x".repeat(ASK_ALL_NOTE_CHARS + 500) } });
    expect(long.length).toBeLessThan(ASK_ALL_NOTE_CHARS + 100);
    expect(long.endsWith(" …")).toBe(true);
  });

  it("citedSources keeps only cited candidates, in first-citation order, once each", () => {
    const c = [
      { minuteId: "a", title: "A", iconEmoji: null, createdAt: null },
      { minuteId: "b", title: "B", iconEmoji: null, createdAt: null },
      { minuteId: "c", title: "C", iconEmoji: null, createdAt: null },
    ];
    const out = citedSources("Friday [[note:b]] and QA [[note:a]] again [[note:b]] unknown [[note:zzz]]", c);
    expect(out.map((s) => s.minuteId)).toEqual(["b", "a"]);
    expect(citedSources("nothing", c)).toEqual([]);
  });
});

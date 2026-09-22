import { describe, expect, it } from "vitest";
import { convertV1Artifact, convertV1Summary, convertV1Transcription, gcsPath, parseClock, splitKeywords } from "../../src/tools/migrateV1.js";

describe("parseClock", () => {
  it("MM:SS and HH:MM:SS", () => { expect(parseClock("15:00")).toBe(900); expect(parseClock("01:02:03")).toBe(3723); });
  it("garbage → null", () => { expect(parseClock("abc")).toBeNull(); expect(parseClock(12)).toBeNull(); });
});

describe("convertV1Transcription", () => {
  it("turns timeRange strings into seconds and keeps speaker ids", () => {
    const t = convertV1Transcription({
      duration: "00:10", transcript: "Hello. Sure.", language_code: "eng", language_probability: 0.9,
      sections: [
        { timeRange: "00:00 - 00:04", title: "Hello.", speaker: "Speaker 1", speaker_id: "speaker_0" },
        { timeRange: "00:05 - 00:10", title: "Sure.", speaker: "Speaker 2", speaker_id: "speaker_1" },
      ],
    })!;
    expect(t.durationSeconds).toBe(10);
    expect(t.segments[1]).toEqual({ startSeconds: 5, endSeconds: 10, text: "Sure.", speakerId: "speaker_1", speakerLabel: "Speaker 2" });
    expect(t.text).toBe("Hello. Sure.");
  });
  it("no transcript text → null (note becomes failed, not a fake ready)", () => {
    expect(convertV1Transcription({ sections: [] })).toBeNull();
    expect(convertV1Transcription(undefined)).toBeNull();
  });
});

describe("convertV1Summary", () => {
  it("maps summaryText → text and keeps sections", () => {
    expect(convertV1Summary({ title: "T", summaryText: "S", icon: "📝", sections: [{ title: "a", bullets: ["b", 1] }] })).toEqual({ title: "T", text: "S", icon: "📝", sections: [{ title: "a", bullets: ["b"] }] });
  });
});

describe("convertV1Artifact", () => {
  it("speakers map → list", () => {
    expect(convertV1Artifact("speakers", { speaker_0: "Ana", speaker_1: "speaker_1", generatedAt: "x" })).toEqual({ speakers: [{ id: "speaker_0", label: "Ana" }, { id: "speaker_1", label: "speaker_1" }] });
  });
  it("quiz: answer string → answerIndex; true/false gets options; short-answer dropped", () => {
    expect(convertV1Artifact("quiz", { quiz: [
      { question: "q1", options: ["A", "B"], answer: "b" },
      { question: "q2", answer: "True" },
      { question: "q3", answer: "free text" },
    ] })).toEqual({ items: [{ question: "q1", options: ["A", "B"], answerIndex: 1 }, { question: "q2", options: ["True", "False"], answerIndex: 0 }] });
  });
  it("mindmap: {mindmap} → {root}, depth clamped to 4 levels, empty root → null", () => {
    const deep = { id: "r", title: "R", icon: "🎯", children: [{ id: "a", title: "A", children: [{ id: "b", title: "B", children: [{ id: "c", title: "C", children: [{ id: "d", title: "D", children: [] }] }] }] }] };
    const out = convertV1Artifact("mindmap", { mindmap: deep }) as { root: { children: { children: { children: { children?: unknown }[] }[] }[] } };
    expect(out.root.children[0]!.children[0]!.children[0]!.children).toBeUndefined();
    expect(convertV1Artifact("mindmap", { mindmap: { title: "Untitled", children: [] } })).toBeNull(); // v1's cached error fallback
  });
  it("shortQuestions and flashcards", () => {
    expect(convertV1Artifact("shortQuestions", { short_questions: ["a", 2] })).toEqual({ questions: ["a"] });
    expect(convertV1Artifact("flashcards", { flashcards: [{ question: "q", answer: "a" }, { bad: 1 }] })).toEqual({ items: [{ question: "q", answer: "a" }] });
    expect(convertV1Artifact("flashcards", { flashcards: [] })).toBeNull();
  });
});

describe("splitKeywords / gcsPath", () => {
  it("string → array, array passes", () => {
    expect(splitKeywords("KPI, A1;  B2 ")).toEqual(["KPI", "A1", "B2"]);
    expect(splitKeywords(["x", "", 3])).toEqual(["x"]);
  });
  it("gs:// → object path; the v1 PDF object bug → null", () => {
    expect(gcsPath("gs://b/user_uploads/u/m/audio/a.m4a")).toBe("user_uploads/u/m/audio/a.m4a");
    expect(gcsPath({ _minuteId: "x", gcsUri: "gs://b/p" })).toBeNull();
  });
});

import type { Transcript, TranscriptSegment } from "../../minutes/types.js";
import type { ElevenLabsResponse } from "./types.js";

/**
 * Word-level Scribe output → speaker-turn segments with NUMERIC seconds.
 * Port of v1's convertElevenLabsToSections, minus the "MM:SS - MM:SS" strings
 * (formatting is the client's job) and with defensive parsing: v1 crashed on a
 * numeric speaker_id (`speakerId.match is not a function`).
 */
export function convertScribe(data: ElevenLabsResponse): Transcript {
  const words = Array.isArray(data.words) ? data.words : [];
  const segments: TranscriptSegment[] = [];

  let cur: { speaker: string; text: string[]; start: number; end: number } | null = null;

  const flush = () => {
    if (!cur || cur.text.length === 0) return;
    segments.push({
      startSeconds: round3(cur.start),
      endSeconds: round3(cur.end),
      text: cur.text.join(" "),
      speakerId: speakerIdOf(cur.speaker),
      speakerLabel: speakerLabelOf(cur.speaker),
    });
  };

  for (const w of words) {
    if (w.type !== "word") continue;
    const text = typeof w.text === "string" ? w.text : "";
    if (!text) continue;
    // Normalise first: Scribe has been seen emitting 1 and "speaker_1" for the same voice.
    const speaker = speakerIdOf(String(w.speaker_id ?? "speaker_0"));
    const start = num(w.start);
    const end = num(w.end);

    if (cur && cur.speaker === speaker) {
      cur.text.push(text);
      cur.end = Math.max(cur.end, end);
    } else {
      flush();
      cur = { speaker, text: [text], start, end };
    }
  }
  flush();

  const last = [...words].reverse().find((w) => w.type === "word");
  const durationSeconds = last ? round3(num(last.end)) : segments.at(-1)?.endSeconds ?? 0;

  return {
    durationSeconds,
    languageCode: typeof data.language_code === "string" ? data.language_code : null,
    languageProbability:
      typeof data.language_probability === "number" ? data.language_probability : null,
    text: typeof data.text === "string" ? data.text : segments.map((s) => s.text).join(" "),
    segments,
  };
}

function num(v: number | string | undefined): number {
  const n = typeof v === "number" ? v : Number.parseFloat(String(v ?? "0"));
  return Number.isFinite(n) ? n : 0;
}
function round3(n: number): number {
  return Math.round(n * 1000) / 1000;
}

/** "speaker_3" | "3" | 3 → "speaker_3" ; anything else passes through. */
export function speakerIdOf(raw: string): string {
  const m = /\d+/.exec(raw);
  return m ? `speaker_${Number.parseInt(m[0], 10)}` : raw;
}
/** "speaker_3" → "Speaker 4" (1-based, as v1 displayed it). */
export function speakerLabelOf(raw: string): string {
  const m = /\d+/.exec(raw);
  return m ? `Speaker ${Number.parseInt(m[0], 10) + 1}` : raw;
}

/** First N characters for the list view / search, on a word boundary. */
export function previewOf(text: string, max = 2000): string {
  if (text.length <= max) return text;
  const cut = text.lastIndexOf(" ", max);
  return text.slice(0, cut > max * 0.8 ? cut : max).trimEnd() + "…";
}

/**
 * S11-01b — transcript chunks with time stamps, so an ask-all answer can cite
 * the exact moment ("[[note:ID@123]]" → the app opens the note and seeks).
 * Stored under users/{uid}/minutes/{id}/chunks/{order} with a vector each.
 */
import type { Transcript, TranscriptSegment } from "../minutes/types.js";

export interface TranscriptChunk {
  order: number;
  text: string;
  startSeconds: number;
  endSeconds: number;
}

/** ~350 words per chunk keeps a chunk inside one topic and well under the embedding limit. */
export const CHUNK_MAX_WORDS = 350;
/** Notes over this many chunks (≈ 4 h of talk) are capped so one note cannot flood the index. */
export const CHUNK_MAX_PER_NOTE = 200;

const words = (s: string) => s.trim().split(/\s+/).filter(Boolean).length;

/**
 * Groups consecutive segments (speaker turns) into chunks of at most
 * CHUNK_MAX_WORDS. A single over-long segment becomes its own chunk. Speaker
 * labels are kept so "what did Ana say" still works.
 */
export function chunkTranscript(t: Transcript, maxWords = CHUNK_MAX_WORDS): TranscriptChunk[] {
  const out: TranscriptChunk[] = [];
  let cur: TranscriptSegment[] = [];
  let curWords = 0;
  const flush = () => {
    if (cur.length === 0) return;
    out.push({
      order: out.length,
      text: cur.map((s) => `${s.speakerLabel || s.speakerId}: ${s.text.trim()}`).join("\n"),
      startSeconds: cur[0]!.startSeconds,
      endSeconds: cur[cur.length - 1]!.endSeconds,
    });
    cur = [];
    curWords = 0;
  };
  for (const seg of t.segments) {
    if (!seg.text.trim()) continue;
    const w = words(seg.text);
    if (cur.length > 0 && curWords + w > maxWords) flush();
    cur.push(seg);
    curWords += w;
    if (out.length >= CHUNK_MAX_PER_NOTE) break;
  }
  flush();
  if (out.length === 0 && t.text.trim()) {
    // No segments (some vendors) — fall back to fixed windows over the text.
    const all = t.text.trim().split(/\s+/);
    for (let i = 0; i < all.length && out.length < CHUNK_MAX_PER_NOTE; i += maxWords) {
      const frac = (n: number) => (t.durationSeconds || 0) * Math.min(1, n / all.length);
      out.push({ order: out.length, text: all.slice(i, i + maxWords).join(" "), startSeconds: Math.floor(frac(i)), endSeconds: Math.ceil(frac(Math.min(all.length, i + maxWords))) });
    }
  }
  return out.slice(0, CHUNK_MAX_PER_NOTE);
}

export const chunkDocId = (order: number) => String(order).padStart(4, "0");

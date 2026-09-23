import { HttpsError } from "firebase-functions/v2/https";
import { chargeAiCall } from "../ai/_artifacts.js";
import type { Deps } from "../lib/deps.js";
import { rethrow } from "../lib/errors.js";
import { requireCaller, type Caller } from "../lib/handler.js";
import { logDone } from "../lib/logging.js";
import { toIso } from "../lib/time.js";
import { parse } from "../lib/validate.js";
import type { MinuteDoc } from "../minutes/_shared.js";
import { ASK_ALL_CONTEXT, ASK_ALL_NOTE, ASK_ALL_SYSTEM } from "../prompts/ai.js";
import { fill } from "../prompts/summarize.js";
import { nearestChunks, nearestMinutes, type ChunkHit, type Neighbour } from "./embedding.js";
import { AskAllInput, SearchNotesInput, type AskAllOutput, type AskAllSource, type SearchNotesOutput } from "./types.js";

/** COSINE distance above this is noise for a short query; the client falls back to its text search. */
export const SEARCH_MAX_DISTANCE = 0.75;
/** Ask-all reads at most this many notes into the prompt. */
export const ASK_ALL_NOTES = 6;
export const ASK_ALL_MAX_DISTANCE = 0.85;
/** Per-note budget inside the prompt so six long notes still fit a cheap model. */
export const ASK_ALL_NOTE_CHARS = 2500;
/** S11-01b: transcript chunks read per question, over all notes. */
export const ASK_ALL_CHUNKS = 12;

interface LoadedNote { minuteId: string; doc: MinuteDoc; distance: number }

async function loadNotes(deps: Deps, uid: string, hits: Neighbour[]): Promise<LoadedNote[]> {
  if (hits.length === 0) return [];
  const snaps = await deps.db.getAll(...hits.map((h) => deps.db.doc(`users/${uid}/minutes/${h.minuteId}`)));
  const out: LoadedNote[] = [];
  snaps.forEach((s, i) => {
    const h = hits[i];
    if (s.exists && h) out.push({ minuteId: s.id, doc: s.data() as MinuteDoc, distance: h.distance });
  });
  return out;
}

/**
 * What the model sees for one note: title, date, summary text and sections,
 * clipped — plus, when chunk retrieval hit this note, the matching transcript
 * passages with their time stamps so the answer can cite `[[note:ID@SECONDS]]`.
 */
export function noteForPrompt(minuteId: string, m: MinuteDoc, maxChars = ASK_ALL_NOTE_CHARS, chunks: ChunkHit[] = []): string {
  const lines: string[] = [];
  const s = m.summary;
  if (s?.text) lines.push(s.text);
  for (const sec of s?.sections ?? []) {
    lines.push(`## ${sec.title}`);
    for (const b of sec.bullets ?? []) lines.push(`- ${b}`);
  }
  let body = lines.join("\n");
  if (body.length > maxChars) body = body.slice(0, maxChars) + " …";
  if (chunks.length > 0) {
    body += "\n\nTranscript passages:";
    for (const c of [...chunks].sort((a, b) => a.startSeconds - b.startSeconds)) {
      let text = c.text;
      if (text.length > maxChars) text = text.slice(0, maxChars) + " …";
      body += `\n[t=${Math.floor(c.startSeconds)}] ${text.replace(/\n/g, " ")}`;
    }
  }
  return fill(ASK_ALL_NOTE, { id: minuteId, title: m.title ?? "", date: toIso(m.createdAt)?.slice(0, 10) ?? "", body });
}

/**
 * Sources actually cited, in citation order, once per note. `[[note:id@123]]`
 * carries the moment the claim comes from; the first citation of a note wins.
 */
export function citedSources(answer: string, candidates: AskAllSource[]): AskAllSource[] {
  const seen = new Set<string>();
  const out: AskAllSource[] = [];
  for (const m of answer.matchAll(/\[\[note:([A-Za-z0-9_-]+)(?:@(\d+))?\]\]/g)) {
    const id = m[1];
    if (!id || seen.has(id)) continue;
    const c = candidates.find((x) => x.minuteId === id);
    if (c) {
      seen.add(id);
      out.push(m[2] !== undefined ? { ...c, startSeconds: Number(m[2]) } : c);
    }
  }
  return out;
}

const toSource = (n: LoadedNote): AskAllSource =>
  ({ minuteId: n.minuteId, title: n.doc.title ?? "", iconEmoji: n.doc.iconEmoji ?? null, createdAt: toIso(n.doc.createdAt) });

export async function searchNotesHandler(caller: Caller | undefined, raw: unknown, deps: Deps): Promise<SearchNotesOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(SearchNotesInput, raw, deps.minClientVersion);
  try {
    const [vector] = await deps.services.embedder.embed([input.query], "query");
    if (!vector) throw new HttpsError("unavailable", "Embedding unavailable");
    const hits = await nearestMinutes(deps.db, uid, vector, input.limit, SEARCH_MAX_DISTANCE);
    const notes = await loadNotes(deps, uid, hits);
    const items = notes.map((n) => ({ ...toSource(n), score: Number((1 - n.distance / 2).toFixed(4)) }));
    logDone("search.notes", startedAt, { uid, hits: items.length });
    return { items };
  } catch (err) {
    return rethrow(err, "search.notes.failed", { uid });
  }
}

export async function askAllHandler(caller: Caller | undefined, raw: unknown, deps: Deps, onDelta?: (delta: string) => void): Promise<AskAllOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(AskAllInput, raw, deps.minClientVersion);
  try {
    await chargeAiCall(deps, uid);
    const [vector] = await deps.services.embedder.embed([input.question], "query");
    if (!vector) throw new HttpsError("unavailable", "Embedding unavailable");
    // Chunk hits (with time stamps) first; notes that only match at summary
    // level fill the remaining slots, so old notes without chunks still count.
    const chunkHits = await nearestChunks(deps.db, uid, vector, ASK_ALL_CHUNKS, ASK_ALL_MAX_DISTANCE);
    const byMinute = new Map<string, ChunkHit[]>();
    for (const h of chunkHits) byMinute.set(h.minuteId, [...(byMinute.get(h.minuteId) ?? []), h]);
    const hits: Neighbour[] = [...byMinute.entries()].map(([minuteId, cs]) => ({ minuteId, distance: Math.min(...cs.map((c) => c.distance)) })).slice(0, ASK_ALL_NOTES);
    if (hits.length < ASK_ALL_NOTES) {
      for (const n of await nearestMinutes(deps.db, uid, vector, ASK_ALL_NOTES, ASK_ALL_MAX_DISTANCE)) {
        if (hits.length >= ASK_ALL_NOTES) break;
        if (!byMinute.has(n.minuteId)) hits.push(n);
      }
    }
    const notes = await loadNotes(deps, uid, hits);
    const candidates = notes.map(toSource);
    const context = notes.length === 0 ? "(no matching notes)" : notes.map((n) => noteForPrompt(n.minuteId, n.doc, ASK_ALL_NOTE_CHARS, byMinute.get(n.minuteId) ?? [])).join("\n\n");

    const { text, model, tokens } = await deps.services.llm.streamText(
      {
        name: "askAll",
        system: fill(ASK_ALL_SYSTEM, { languageCode: input.languageCode }) + "\n\n" + fill(ASK_ALL_CONTEXT, { notes: context }),
        history: input.history,
        prompt: input.question,
        maxOutputTokens: 1200,
      },
      onDelta ?? (() => undefined),
    );
    const sources = citedSources(text, candidates);
    logDone("search.askAll", startedAt, { uid, chunkHits: chunkHits.length, candidates: candidates.length, cited: sources.length, model, tokensIn: tokens.input, tokensOut: tokens.output });
    return { answer: text, sources };
  } catch (err) {
    return rethrow(err, "search.askAll.failed", { uid });
  }
}

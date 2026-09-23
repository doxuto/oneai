import { FieldValue } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { z } from "zod";
import type { Deps } from "../lib/deps.js";
import { rethrow } from "../lib/errors.js";
import { requireCaller, type Caller } from "../lib/handler.js";
import { logDone } from "../lib/logging.js";
import { parse } from "../lib/validate.js";
import { toSummary } from "../minutes/_shared.js";
import type { Summary } from "../minutes/types.js";
import { TRANSLATE_SYSTEM } from "../prompts/ai.js";
import { fill } from "../prompts/summarize.js";
import { DocId, LanguageCode, withClient } from "../types/common.js";
import { chargeAiCall, loadReadyTranscript, transcriptBySpeaker } from "./_artifacts.js";

export const TranslatePart = z.enum(["summary", "transcript"]);
export type TranslatePart = z.infer<typeof TranslatePart>;

export const TranslateInput = withClient({
  minuteId: DocId,
  part: TranslatePart,
  languageCode: LanguageCode,
  force: z.boolean().default(false),
}).strict();
export type TranslateInput = z.infer<typeof TranslateInput>;

export interface TranslateOutput {
  part: TranslatePart;
  languageCode: string;
  text: string;
  cached: boolean;
}

/** Plain-text rendering of a summary that survives translation (headings kept as lines). */
export function summaryAsText(s: Summary): string {
  const out: string[] = [];
  if (s.title) out.push(`# ${s.title}`);
  if (s.text) out.push("", s.text);
  for (const sec of s.sections) {
    out.push("", `## ${sec.title}`);
    for (const b of sec.bullets) out.push(b);
  }
  return out.join("\n").trim();
}

/**
 * Split on line boundaries into chunks of at most `max` chars, so each model
 * call stays well inside its output budget and a 2-hour transcript never
 * truncates. A single over-long line becomes its own chunk.
 */
export function chunkLines(text: string, max = 6000): string[] {
  const chunks: string[] = [];
  let cur = "";
  for (const line of text.split("\n")) {
    if (cur.length > 0 && cur.length + 1 + line.length > max) {
      chunks.push(cur);
      cur = line;
    } else {
      cur = cur.length === 0 ? line : `${cur}\n${line}`;
    }
  }
  if (cur.length > 0) chunks.push(cur);
  return chunks;
}

const CHUNK_MAX_OUTPUT_TOKENS = 3000;

export async function translateHandler(
  caller: Caller | undefined,
  raw: unknown,
  deps: Deps,
  onDelta?: (delta: string) => void,
): Promise<TranslateOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(TranslateInput, raw, deps.minClientVersion);
  try {
    const loaded = await loadReadyTranscript(deps, uid, input.minuteId);
    const ref = loaded.minuteRef.collection("translations").doc(`${input.part}_${input.languageCode}`);

    if (!input.force) {
      const snap = await ref.get();
      const d = snap.data() as { sourceHash?: string; text?: string } | undefined;
      if (d && d.sourceHash === loaded.sourceHash && typeof d.text === "string" && d.text.length > 0) {
        logDone("ai.translate", startedAt, { uid, minuteId: input.minuteId, part: input.part, languageCode: input.languageCode, cached: true });
        return { part: input.part, languageCode: input.languageCode, text: d.text, cached: true };
      }
    }

    let source: string;
    if (input.part === "summary") {
      const summary = toSummary(loaded.minuteDoc.summary);
      if (!summary) throw new HttpsError("failed-precondition", "This note has no summary", { reason: "noSummary" });
      source = summaryAsText(summary);
    } else {
      source = transcriptBySpeaker(loaded.transcript);
    }

    await chargeAiCall(deps, uid); // one call against the daily cap, however many chunks
    const system = fill(TRANSLATE_SYSTEM, { languageCode: input.languageCode });
    const parts: string[] = [];
    let model = "";
    let tokensIn = 0;
    let tokensOut = 0;
    const chunks = chunkLines(source);
    for (let i = 0; i < chunks.length; i++) {
      const chunk = chunks[i] ?? "";
      const r = await deps.services.llm.streamText(
        { name: `translate.${input.part}`, system, prompt: chunk, maxOutputTokens: CHUNK_MAX_OUTPUT_TOKENS, temperature: 0.2 },
        (delta) => { onDelta?.(delta); },
      );
      parts.push(r.text);
      model = r.model;
      tokensIn += r.tokens.input;
      tokensOut += r.tokens.output;
      if (i < chunks.length - 1) onDelta?.("\n");
    }
    const text = parts.join("\n");
    await ref.set({
      part: input.part, languageCode: input.languageCode, text, sourceHash: loaded.sourceHash, model,
      chunks: chunks.length, generatedAt: FieldValue.serverTimestamp(),
    });
    logDone("ai.translate", startedAt, { uid, minuteId: input.minuteId, part: input.part, languageCode: input.languageCode, cached: false, model, chunks: chunks.length, tokensIn, tokensOut });
    return { part: input.part, languageCode: input.languageCode, text, cached: false };
  } catch (err) {
    return rethrow(err, "ai.translate.failed", { uid, minuteId: input.minuteId });
  }
}

import { createHash } from "node:crypto";
import { FieldValue, type DocumentData, type Firestore, type Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import type { Deps } from "../lib/deps.js";
import { rethrow } from "../lib/errors.js";
import { requireCaller, type Caller } from "../lib/handler.js";
import { logDone } from "../lib/logging.js";
import { toIso } from "../lib/time.js";
import { parse } from "../lib/validate.js";
import {
  DeleteGlossaryTermInput, ListGlossaryInput, MAX_GLOSSARY_TERMS, MAX_KEYTERMS_PER_JOB, UpsertGlossaryTermInput,
  type DeleteGlossaryTermOutput, type GlossaryTerm, type ListGlossaryOutput, type UpsertGlossaryTermOutput,
} from "./types.js";

export const glossaryCol = (db: Firestore, uid: string) => db.collection(`users/${uid}/glossary`);

/** Same term in any casing/spacing is one entry: the id is derived from it. */
export const termId = (term: string): string =>
  createHash("sha1").update(term.trim().toLowerCase().replace(/\s+/g, " ")).digest("hex").slice(0, 20);

export function toGlossaryTerm(id: string, d: DocumentData | undefined): GlossaryTerm {
  const x = (d ?? {}) as { term?: unknown; hint?: unknown; createdAt?: Timestamp };
  return {
    id,
    term: typeof x.term === "string" ? x.term : "",
    hint: typeof x.hint === "string" && x.hint ? x.hint : null,
    createdAt: toIso(x.createdAt ?? null) ?? "1970-01-01T00:00:00.000Z",
  };
}

/**
 * Pure: the per-job keyterm list = the user's one-off keywords first, then
 * glossary terms, de-duplicated case-insensitively, capped. Order matters
 * because STT prompts get truncated from the end.
 */
export function mergeKeyterms(keywords: string[], glossary: string[], max = MAX_KEYTERMS_PER_JOB): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const t of [...keywords, ...glossary]) {
    const k = t.trim();
    const key = k.toLowerCase();
    if (!k || seen.has(key)) continue;
    seen.add(key);
    out.push(k);
    if (out.length >= max) break;
  }
  return out;
}

/** Terms for a job, oldest first (the ones the user cared about first). */
export async function glossaryTermsFor(db: Firestore, uid: string): Promise<string[]> {
  const snap = await glossaryCol(db, uid).orderBy("createdAt", "asc").limit(MAX_KEYTERMS_PER_JOB).get();
  return snap.docs.map((d) => toGlossaryTerm(d.id, d.data())).map((t) => (t.hint ? `${t.term} (${t.hint})` : t.term));
}

export async function listGlossaryHandler(caller: Caller | undefined, raw: unknown, deps: Deps): Promise<ListGlossaryOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  parse(ListGlossaryInput, raw, deps.minClientVersion);
  try {
    const snap = await glossaryCol(deps.db, uid).orderBy("createdAt", "asc").limit(MAX_GLOSSARY_TERMS).get();
    const items = snap.docs.map((d) => toGlossaryTerm(d.id, d.data()));
    logDone("glossary.list", startedAt, { uid, count: items.length });
    return { items };
  } catch (err) {
    return rethrow(err, "glossary.list.failed", { uid });
  }
}

export async function upsertGlossaryTermHandler(caller: Caller | undefined, raw: unknown, deps: Deps): Promise<UpsertGlossaryTermOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(UpsertGlossaryTermInput, raw, deps.minClientVersion);
  try {
    const id = termId(input.term);
    const ref = glossaryCol(deps.db, uid).doc(id);
    await deps.db.runTransaction(async (tx) => {
      const cur = await tx.get(ref);
      if (!cur.exists) {
        const count = await tx.get(glossaryCol(deps.db, uid).count());
        if (count.data().count >= MAX_GLOSSARY_TERMS) {
          throw new HttpsError("resource-exhausted", "Glossary is full", { reason: "glossaryFull", limit: MAX_GLOSSARY_TERMS });
        }
      }
      tx.set(ref, {
        term: input.term,
        hint: input.hint ?? null,
        createdAt: cur.exists ? (cur.data() as { createdAt?: unknown }).createdAt : FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      }, { merge: true });
    });
    const after = await ref.get();
    logDone("glossary.upsert", startedAt, { uid, termId: id });
    return { term: toGlossaryTerm(id, after.data()) };
  } catch (err) {
    return rethrow(err, "glossary.upsert.failed", { uid });
  }
}

export async function deleteGlossaryTermHandler(caller: Caller | undefined, raw: unknown, deps: Deps): Promise<DeleteGlossaryTermOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(DeleteGlossaryTermInput, raw, deps.minClientVersion);
  try {
    await glossaryCol(deps.db, uid).doc(input.termId).delete();
    logDone("glossary.delete", startedAt, { uid, termId: input.termId });
    return {};
  } catch (err) {
    return rethrow(err, "glossary.delete.failed", { uid, termId: input.termId });
  }
}

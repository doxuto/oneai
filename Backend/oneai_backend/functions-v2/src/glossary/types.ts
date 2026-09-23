import { z } from "zod";
import { DocId, withClient } from "../types/common.js";

/** A name, product or piece of jargon the models should spell exactly. */
export const Term = z.string().trim().min(1).max(60);
export const Hint = z.string().trim().max(120);

export const ListGlossaryInput = withClient({});
export const UpsertGlossaryTermInput = withClient({ term: Term, hint: Hint.optional() }).strict();
export const DeleteGlossaryTermInput = withClient({ termId: DocId }).strict();

export interface GlossaryTerm {
  id: string;
  term: string;
  /** "our CFO", "product, not the fruit" — shown to the summariser too. */
  hint: string | null;
  createdAt: string;
}
export interface ListGlossaryOutput { items: GlossaryTerm[] }
export interface UpsertGlossaryTermOutput { term: GlossaryTerm }
export type DeleteGlossaryTermOutput = Record<string, never>;

/** Cap per user; also the most we hand to STT / the summariser. */
export const MAX_GLOSSARY_TERMS = 200;
export const MAX_KEYTERMS_PER_JOB = 60;

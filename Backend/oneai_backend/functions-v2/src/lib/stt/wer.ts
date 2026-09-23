/**
 * Word error rate for the STT benchmark (S11-13). Pure: normalise both texts
 * the same way (lower-case, Unicode NFC, strip punctuation, collapse spaces —
 * Vietnamese diacritics are KEPT, they change the word), then Levenshtein
 * over word arrays. Character error rate too, which is fairer for Vietnamese
 * where a wrong tone mark is one character but a whole "word" error.
 */

export function normalizeForWer(text: string): string[] {
  return text
    .normalize("NFC")
    .toLowerCase()
    .replace(/[\p{P}\p{S}]+/gu, " ")
    .split(/\s+/)
    .filter(Boolean);
}

/** Levenshtein distance over any token sequence — O(n·m) memory-light. */
export function editDistance<T>(a: readonly T[], b: readonly T[]): number {
  if (a.length === 0) return b.length;
  if (b.length === 0) return a.length;
  let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    const cur = [i];
    for (let j = 1; j <= b.length; j++) {
      cur[j] = Math.min(prev[j]! + 1, cur[j - 1]! + 1, prev[j - 1]! + (a[i - 1] === b[j - 1] ? 0 : 1));
    }
    prev = cur;
  }
  return prev[b.length]!;
}

export interface ErrorRates { wer: number; cer: number; refWords: number; hypWords: number }

/** Rates in [0, ∞): an empty reference with a non-empty hypothesis is 1.0 per inserted token. */
export function errorRates(reference: string, hypothesis: string): ErrorRates {
  const r = normalizeForWer(reference);
  const h = normalizeForWer(hypothesis);
  const wer = r.length === 0 ? (h.length === 0 ? 0 : 1) : editDistance(r, h) / r.length;
  const rc = [...r.join(" ")];
  const hc = [...h.join(" ")];
  const cer = rc.length === 0 ? (hc.length === 0 ? 0 : 1) : editDistance(rc, hc) / rc.length;
  return { wer, cer, refWords: r.length, hypWords: h.length };
}

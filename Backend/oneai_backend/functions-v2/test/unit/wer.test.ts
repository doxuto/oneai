import { describe, expect, it } from "vitest";
import { editDistance, errorRates, normalizeForWer } from "../../src/lib/stt/wer.js";

describe("WER / CER (S11-13)", () => {
  it("normalises case, punctuation and spacing but keeps Vietnamese diacritics", () => {
    expect(normalizeForWer("Xin chào,  VinFast!  (Hà Nội)")).toEqual(["xin", "chào", "vinfast", "hà", "nội"]);
    expect(normalizeForWer("hoà")).toEqual(["hoà".normalize("NFC")]);
  });
  it("edit distance", () => {
    expect(editDistance([], ["a"])).toBe(1);
    expect(editDistance(["a", "b", "c"], ["a", "x", "c", "d"])).toBe(2);
  });
  it("rates: exact = 0; a wrong tone mark is one word but one character", () => {
    expect(errorRates("chúng ta giao hàng thứ sáu", "Chúng ta giao hàng thứ sáu.")).toMatchObject({ wer: 0, cer: 0, refWords: 6 });
    const r = errorRates("chúng ta giao hàng thứ sáu", "chúng ta giao hang thứ sáu");
    expect(r.wer).toBeCloseTo(1 / 6);
    expect(r.cer).toBeCloseTo(1 / [..."chúng ta giao hàng thứ sáu"].length);
    expect(errorRates("", "")).toMatchObject({ wer: 0, cer: 0 });
    expect(errorRates("", "x y")).toMatchObject({ wer: 1 });
    expect(errorRates("a b", "").wer).toBe(1);
  });
});

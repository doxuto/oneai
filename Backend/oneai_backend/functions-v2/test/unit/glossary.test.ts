import { describe, expect, it } from "vitest";
import { deleteGlossaryTermHandler, listGlossaryHandler, mergeKeyterms, termId, upsertGlossaryTermHandler } from "../../src/glossary/handler.js";
import { UpsertGlossaryTermInput } from "../../src/glossary/types.js";
import { unitDeps } from "../../src/lib/deps.js";
import { sttPrompt } from "../../src/lib/stt/gemini.js";

const client = { appVersion: "2.0.0", build: 1, platform: "ios" as const };
const caller = { uid: "u1", signInProvider: "google.com" };

describe("glossary (S11-10)", () => {
  it("termId is case/space-insensitive so 'VinFast' and ' vinfast ' are one entry", () => {
    expect(termId("VinFast")).toBe(termId(" vinfast "));
    expect(termId("Vin Fast")).not.toBe(termId("VinFast"));
    expect(termId("x")).toMatch(/^[0-9a-f]{20}$/);
  });
  it("input: term 1..60 chars trimmed, hint ≤120, no extra keys", () => {
    expect(UpsertGlossaryTermInput.parse({ client, term: "  Ana  " }).term).toBe("Ana");
    expect(() => UpsertGlossaryTermInput.parse({ client, term: "" })).toThrow();
    expect(() => UpsertGlossaryTermInput.parse({ client, term: "a".repeat(61) })).toThrow();
    expect(() => UpsertGlossaryTermInput.parse({ client, term: "a", extra: 1 })).toThrow();
  });
  it("mergeKeyterms: keywords first, glossary after, case-insensitive dedupe, capped", () => {
    expect(mergeKeyterms(["Ana", "roadmap"], ["ana", "Q4 OKR", " roadmap "])).toEqual(["Ana", "roadmap", "Q4 OKR"]);
    expect(mergeKeyterms([], Array.from({ length: 100 }, (_, i) => `t${i}`)).length).toBe(60);
    expect(mergeKeyterms(["", "  "], [])).toEqual([]);
  });
  it("Gemini STT prompt lists the terms only when there are any", () => {
    expect(sttPrompt("vie")).not.toContain("spell them exactly");
    expect(sttPrompt("vie", ["VinFast", "Ana (our CFO)"])).toContain('"VinFast", "Ana (our CFO)"');
  });
  it("handlers require auth before touching db", async () => {
    await expect(listGlossaryHandler(undefined, { client }, unitDeps())).rejects.toMatchObject({ code: "unauthenticated" });
    await expect(upsertGlossaryTermHandler(undefined, { client, term: "x" }, unitDeps())).rejects.toMatchObject({ code: "unauthenticated" });
    await expect(deleteGlossaryTermHandler(caller, { client, termId: "a/b" }, unitDeps())).rejects.toMatchObject({ code: "invalid-argument" });
  });
});

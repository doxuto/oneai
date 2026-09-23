import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { pickDoc } from "../../src/legal/legal.js";

const asset = (n: string) => readFileSync(fileURLToPath(new URL(`../../assets/legal/${n}`, import.meta.url)), "utf8");

describe("legal pages (S10-07)", () => {
  it("pickDoc defaults to privacy/en and only accepts known docs and langs", () => {
    expect(pickDoc({})).toEqual({ doc: "privacy", lang: "en" });
    expect(pickDoc({ doc: "terms", lang: "vi-VN" })).toEqual({ doc: "terms", lang: "vi" });
    expect(pickDoc({ doc: "../etc/passwd", lang: "fr" })).toEqual({ doc: "privacy", lang: "en" });
    expect(pickDoc({ asset: "style" })).toEqual({ asset: "style" });
  });
  it("all six pages exist, state the product facts, and cross-link", () => {
    for (const doc of ["privacy", "terms", "delete-account"]) {
      for (const lang of ["en", "vi"]) {
        const html = asset(`${doc}.${lang}.html`);
        expect(html).toContain(`<html lang="${lang}">`);
        expect(html).toContain("contact@doxutostudio.top");
        expect(html).toContain(`lang=${lang === "en" ? "vi" : "en"}`); // language switch
      }
    }
    const p = asset("privacy.en.html");
    for (const s of ["7 days", "90 days", "ElevenLabs", "Gemini", "OpenAI", "RevenueCat", "AdMob", "not used to train"]) expect(p).toContain(s);
    const t = asset("terms.en.html");
    for (const s of ["10 minutes of audio per day", "5 minutes", "4 hours", "Vietnam"]) expect(t).toContain(s);
    expect(asset("terms.vi.html")).toContain("10 phút audio mỗi ngày");
  });
});

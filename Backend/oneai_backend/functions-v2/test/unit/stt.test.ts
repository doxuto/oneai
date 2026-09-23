import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { convertScribe, previewOf, speakerIdOf, speakerLabelOf } from "../../src/lib/stt/convert.js";
import { HttpsError, type FunctionsErrorCode } from "firebase-functions/v2/https";
import { elevenLabsClient } from "../../src/lib/stt/elevenlabs.js";
import { geminiMime, geminiSttClient } from "../../src/lib/stt/gemini.js";
import { makeStt, parseSttVendor, withSttFallback } from "../../src/lib/stt/index.js";
import { sttLanguageCode } from "../../src/lib/stt/languages.js";
import type { ElevenLabsResponse, SttClient } from "../../src/lib/stt/types.js";

const fixture = JSON.parse(
  readFileSync(fileURLToPath(new URL("../fixtures/scribe-small.json", import.meta.url)), "utf8"),
) as ElevenLabsResponse;

describe("sttLanguageCode", () => {
  it("auto and auto-detect mean undefined", () => {
    expect(sttLanguageCode("auto")).toBeUndefined();
    expect(sttLanguageCode("auto-detect")).toBeUndefined();
    expect(sttLanguageCode(undefined)).toBeUndefined();
  });
  it("passes ISO-639-3 through", () => expect(sttLanguageCode("vie")).toBe("vie"));
  it("maps BCP-47 prefixes", () => {
    expect(sttLanguageCode("en-US")).toBe("eng");
    expect(sttLanguageCode("vi")).toBe("vie");
    expect(sttLanguageCode("zh-Hant")).toBe("zho");
  });
  it("unknown → undefined (let the model detect) rather than an error", () =>
    expect(sttLanguageCode("klingon")).toBeUndefined());
});

describe("convertScribe", () => {
  const t = convertScribe(fixture);

  it("groups words into speaker turns and skips spacing/audio events", () => {
    expect(t.segments).toHaveLength(2);
    expect(t.segments[0]?.text).toBe("Hello everyone. Let's start.");
    expect(t.segments[1]?.text).toBe("Sure, go ahead.");
  });

  it("uses numeric seconds — no 'MM:SS - MM:SS' strings", () => {
    expect(t.segments[0]).toMatchObject({ startSeconds: 0, endSeconds: 2.4 });
    expect(t.segments[1]).toMatchObject({ startSeconds: 3, endSeconds: 3.9 });
    expect(t.durationSeconds).toBe(3.9);
  });

  it("survives a numeric speaker_id and a string end (v1 crashed on both)", () => {
    expect(t.segments[1]?.speakerId).toBe("speaker_1");
    expect(t.segments[1]?.speakerLabel).toBe("Speaker 2");
  });

  it("carries language fields and the full text", () => {
    expect(t.languageCode).toBe("eng");
    expect(t.languageProbability).toBe(0.97);
    expect(t.text).toBe("Hello everyone. Let's start. Sure, go ahead.");
  });

  it("handles an empty response without throwing", () => {
    expect(convertScribe({})).toEqual({
      durationSeconds: 0, languageCode: null, languageProbability: null, text: "", segments: [],
    });
  });

  it("speaker helpers", () => {
    expect(speakerIdOf("speaker_7")).toBe("speaker_7");
    expect(speakerIdOf("7")).toBe("speaker_7");
    expect(speakerLabelOf("speaker_0")).toBe("Speaker 1");
    expect(speakerIdOf("unknown")).toBe("unknown");
  });
});

describe("previewOf", () => {
  it("returns short text untouched", () => expect(previewOf("hi")).toBe("hi"));
  it("cuts on a word boundary and appends an ellipsis", () => {
    const p = previewOf("word ".repeat(1000), 100);
    expect(p.length).toBeLessThanOrEqual(101);
    expect(p.endsWith("…")).toBe(true);
    expect(p).not.toMatch(/ …$/);
  });
});

describe("elevenLabsClient", () => {
  const req = { audio: new Uint8Array([1, 2, 3]), contentType: "audio/mpeg", fileName: "a.mp3", languageCode: "vie" };

  it("sends the right form fields and header, returns parsed JSON", async () => {
    let captured: { url: string; init: RequestInit } | undefined;
    const fetchImpl: typeof fetch = async (url, init) => {
      captured = { url: String(url), init: init ?? {} };
      return new Response(JSON.stringify(fixture), { status: 200 });
    };
    const client = elevenLabsClient({ apiKey: "k", model: "scribe_v1", timeoutMs: 5000, fetchImpl });
    const out = await client.transcribe(req);
    expect(out.vendor).toBe("elevenlabs");
    expect(out.model).toBe("scribe_v1");
    expect(out.transcript.languageCode).toBe("eng");
    expect(out.transcript.segments.length).toBeGreaterThan(0);
    expect(captured?.url).toContain("speech-to-text");
    expect((captured?.init.headers as Record<string, string>)["xi-api-key"]).toBe("k");
    const form = captured?.init.body as FormData;
    expect(form.get("model_id")).toBe("scribe_v1");
    expect(form.get("diarize")).toBe("true");
    expect(form.get("language_code")).toBe("vie");
    expect(form.get("file")).toBeInstanceOf(Blob);
  });

  it("omits language_code for auto-detect", async () => {
    let form: FormData | undefined;
    const fetchImpl: typeof fetch = async (_u, init) => { form = init?.body as FormData; return new Response("{}", { status: 200 }); };
    await elevenLabsClient({ apiKey: "k", model: "m", timeoutMs: 5000, fetchImpl }).transcribe({ ...req, languageCode: undefined });
    expect(form?.has("language_code")).toBe(false);
  });

  it("429 → resource-exhausted", async () => {
    const fetchImpl: typeof fetch = async () => new Response("slow down", { status: 429 });
    await expect(elevenLabsClient({ apiKey: "k", model: "m", timeoutMs: 5000, fetchImpl }).transcribe(req))
      .rejects.toMatchObject({ code: "resource-exhausted" });
  });

  it("5xx → unavailable", async () => {
    const fetchImpl: typeof fetch = async () => new Response("boom", { status: 503 });
    await expect(elevenLabsClient({ apiKey: "k", model: "m", timeoutMs: 5000, fetchImpl }).transcribe(req))
      .rejects.toMatchObject({ code: "unavailable" });
  });

  it("4xx we caused → internal (never explained to the client)", async () => {
    const fetchImpl: typeof fetch = async () => new Response("bad file", { status: 400 });
    await expect(elevenLabsClient({ apiKey: "k", model: "m", timeoutMs: 5000, fetchImpl }).transcribe(req))
      .rejects.toMatchObject({ code: "internal" });
  });

  it("network failure → unavailable", async () => {
    const fetchImpl: typeof fetch = async () => { throw new TypeError("fetch failed"); };
    await expect(elevenLabsClient({ apiKey: "k", model: "m", timeoutMs: 5000, fetchImpl }).transcribe(req))
      .rejects.toMatchObject({ code: "unavailable" });
  });

  it("times out with deadline-exceeded, not a platform kill", async () => {
    const fetchImpl: typeof fetch = (_u, init) =>
      new Promise((_res, rej) => init?.signal?.addEventListener("abort", () => rej(init.signal?.reason)));
    await expect(elevenLabsClient({ apiKey: "k", model: "m", timeoutMs: 20, fetchImpl }).transcribe(req))
      .rejects.toMatchObject({ code: "deadline-exceeded" });
  });
});

describe("geminiSttClient", () => {
  const req = { audio: new Uint8Array([1, 2, 3]), contentType: "audio/x-m4a", fileName: "a.m4a", languageCode: "vie" };
  const reply = (obj: unknown, extra: Record<string, unknown> = {}) =>
    new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: JSON.stringify(obj) }] } }], usageMetadata: { promptTokenCount: 10, candidatesTokenCount: 5 }, ...extra }), { status: 200 });
  const good = { language_code: "vie", segments: [
    { start: 0, end: 1.5, speaker: "speaker_0", text: "Xin chào" },
    { start: 1.5, end: 3, speaker: "speaker_1", text: "Chào bạn" },
    { start: 3, end: 3.2, speaker: "speaker_1", text: "   " },
  ] };

  it("small file: inline base64, prompt carries the language, canonical MIME, normalised transcript", async () => {
    let body: Record<string, unknown> | undefined;
    let url = "";
    const fetchImpl: typeof fetch = async (u, init) => { url = String(u); body = JSON.parse(String(init?.body)) as Record<string, unknown>; return reply(good); };
    const out = await geminiSttClient({ apiKey: "k", model: "gemini-2.5-flash", timeoutMs: 5000, fetchImpl }).transcribe(req);
    expect(url).toContain("/v1beta/models/gemini-2.5-flash:generateContent?key=k");
    const parts = (body!.contents as { parts: Record<string, unknown>[] }[])[0]!.parts;
    expect(String(parts[0]!.text)).toContain("'vie'");
    expect(parts[1]!.inline_data).toEqual({ mime_type: "audio/aac", data: Buffer.from([1, 2, 3]).toString("base64") });
    expect((body!.generationConfig as { responseMimeType: string }).responseMimeType).toBe("application/json");
    expect(out.vendor).toBe("gemini");
    expect(out.transcript.languageCode).toBe("vie");
    expect(out.transcript.segments).toHaveLength(2); // blank segment dropped
    expect(out.transcript.segments[1]).toEqual({ startSeconds: 1.5, endSeconds: 3, text: "Chào bạn", speakerId: "speaker_1", speakerLabel: "Speaker 2" });
    expect(out.transcript.durationSeconds).toBe(3);
    expect(out.transcript.text).toBe("Xin chào Chào bạn");
    expect(out.transcript.languageProbability).toBeNull();
  });

  it("large file: uploads via the Files API, polls until ACTIVE, references the URI, deletes afterwards", async () => {
    const calls: string[] = [];
    let pollCount = 0;
    const fetchImpl: typeof fetch = async (u, init) => {
      const url = String(u);
      calls.push(`${init?.method ?? "GET"} ${url.split("?")[0]}`);
      if (url.includes("/upload/v1beta/files")) {
        expect((init?.headers as Record<string, string>)["X-Goog-Upload-Protocol"]).toBe("raw");
        return new Response(JSON.stringify({ file: { uri: "https://files/abc", name: "files/abc", state: "PROCESSING" } }), { status: 200 });
      }
      if (url.includes("/v1beta/files/abc") && init?.method === "GET") {
        pollCount++;
        return new Response(JSON.stringify({ state: pollCount >= 2 ? "ACTIVE" : "PROCESSING", uri: "https://files/abc" }), { status: 200 });
      }
      if (init?.method === "DELETE") return new Response("", { status: 200 });
      const body = JSON.parse(String(init?.body)) as { contents: { parts: Record<string, unknown>[] }[] };
      expect(body.contents[0]!.parts[1]!.file_data).toEqual({ mime_type: "audio/aac", file_uri: "https://files/abc" });
      return reply(good);
    };
    const out = await geminiSttClient({ apiKey: "k", model: "m", timeoutMs: 20000, fetchImpl, inlineMaxBytes: 2, pollIntervalMs: 1 }).transcribe(req);
    expect(out.transcript.segments).toHaveLength(2);
    expect(pollCount).toBe(2);
    await new Promise((r) => setTimeout(r, 0));
    expect(calls.at(-1)).toBe("DELETE https://generativelanguage.googleapis.com/v1beta/files/abc");
  });

  it("auto-detect prompt asks the model to detect", async () => {
    let text = "";
    const fetchImpl: typeof fetch = async (_u, init) => { const b = JSON.parse(String(init?.body)) as { contents: { parts: { text?: string }[] }[] }; text = b.contents[0]!.parts[0]!.text ?? ""; return reply(good); };
    await geminiSttClient({ apiKey: "k", model: "m", timeoutMs: 5000, fetchImpl }).transcribe({ ...req, languageCode: undefined });
    expect(text).toContain("Detect the spoken language");
  });

  it("safety block → failed-precondition/safety; malformed or off-schema JSON → unavailable", async () => {
    const mk = (fetchImpl: typeof fetch) => geminiSttClient({ apiKey: "k", model: "m", timeoutMs: 5000, fetchImpl });
    await expect(mk(async () => reply(good, { promptFeedback: { blockReason: "SAFETY" } })).transcribe(req)).rejects.toMatchObject({ code: "failed-precondition", details: { reason: "safety" } });
    await expect(mk(async () => new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: "not json" }] } }] }), { status: 200 })).transcribe(req)).rejects.toMatchObject({ code: "unavailable" });
    await expect(mk(async () => reply({ segments: "nope" })).transcribe(req)).rejects.toMatchObject({ code: "unavailable" });
  });

  it("maps 429 / 5xx / network / timeout like every other provider", async () => {
    const mk = (fetchImpl: typeof fetch, timeoutMs = 5000) => geminiSttClient({ apiKey: "k", model: "m", timeoutMs, fetchImpl });
    await expect(mk(async () => new Response("", { status: 429 })).transcribe(req)).rejects.toMatchObject({ code: "resource-exhausted" });
    await expect(mk(async () => new Response("", { status: 503 })).transcribe(req)).rejects.toMatchObject({ code: "unavailable" });
    await expect(mk(async () => { throw new TypeError("fetch failed"); }).transcribe(req)).rejects.toMatchObject({ code: "unavailable" });
    const hang: typeof fetch = (_u, init) => new Promise((_res, rej) => init?.signal?.addEventListener("abort", () => rej(init.signal?.reason)));
    await expect(mk(hang, 20).transcribe(req)).rejects.toMatchObject({ code: "deadline-exceeded" });
  });

  it("geminiMime canonicalises container aliases and passes unknown audio through", () => {
    expect(geminiMime("audio/x-m4a")).toBe("audio/aac");
    expect(geminiMime("audio/mpeg; charset=binary")).toBe("audio/mp3");
    expect(geminiMime("audio/x-wav")).toBe("audio/wav");
    expect(geminiMime("audio/amr")).toBe("audio/amr");
    expect(geminiMime("application/octet-stream")).toBe("audio/mp3");
  });
});

describe("STT factory + fallback", () => {
  const ok = (vendor: string): SttClient => ({ vendor, model: "m", transcribe: async () => ({ vendor, model: "m", transcript: { durationSeconds: 1, languageCode: "eng", languageProbability: null, text: "hi", segments: [] } }) });
  const failing = (vendor: string, code: FunctionsErrorCode): SttClient & { calls: number } => {
    const c = { vendor, model: "m", calls: 0, async transcribe() { c.calls++; throw new HttpsError(code, "x"); } };
    return c;
  };
  const req = { audio: new Uint8Array(), contentType: "audio/mp3", fileName: "a", languageCode: undefined };

  it("parseSttVendor accepts the two vendors, case-insensitively, and nothing else", () => {
    expect(parseSttVendor("Gemini")).toBe("gemini");
    expect(parseSttVendor("elevenlabs")).toBe("elevenlabs");
    expect(parseSttVendor("none")).toBeNull();
    expect(parseSttVendor(undefined)).toBeNull();
  });

  it("makeStt builds the adapter for each vendor", async () => {
    const cfg = { elevenlabs: { apiKey: "a", model: "scribe_v1" }, gemini: { apiKey: "b", model: "g" }, timeoutMs: 1 };
    expect((await makeStt("elevenlabs", cfg)).vendor).toBe("elevenlabs");
    expect((await makeStt("gemini", cfg)).model).toBe("g");
  });

  it("falls back on vendor-side errors only", async () => {
    const p = failing("elevenlabs", "unavailable");
    const out = await withSttFallback(p, ok("gemini")).transcribe(req);
    expect(out.vendor).toBe("gemini");
    expect(p.calls).toBe(1);

    const safety = failing("elevenlabs", "failed-precondition");
    await expect(withSttFallback(safety, ok("gemini")).transcribe(req)).rejects.toMatchObject({ code: "failed-precondition" });

    const slow = failing("elevenlabs", "deadline-exceeded");
    await expect(withSttFallback(slow, ok("gemini")).transcribe(req)).rejects.toMatchObject({ code: "deadline-exceeded" });
  });

  it("when both fail, the secondary's error surfaces", async () => {
    await expect(withSttFallback(failing("a", "unavailable"), failing("b", "resource-exhausted")).transcribe(req)).rejects.toMatchObject({ code: "resource-exhausted" });
  });
});

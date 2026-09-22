import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";
import { convertScribe, previewOf, speakerIdOf, speakerLabelOf } from "../../src/lib/stt/convert.js";
import { elevenLabsClient } from "../../src/lib/stt/elevenlabs.js";
import { sttLanguageCode } from "../../src/lib/stt/languages.js";
import type { ElevenLabsResponse } from "../../src/lib/stt/types.js";

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
    expect(out.language_code).toBe("eng");
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

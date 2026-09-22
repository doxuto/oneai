import { describe, expect, it } from "vitest";
import { z } from "zod";
import { geminiClient } from "../../src/lib/llm/gemini.js";
import { makeLlm, parseVendor } from "../../src/lib/llm/index.js";

const schema = z.object({ a: z.number() });
function fake(reply: unknown, extra: Record<string, unknown> = {}) {
  let captured: Record<string, unknown> | undefined;
  const fetchImpl: typeof fetch = async (_u, init) => {
    captured = JSON.parse(String(init?.body)) as Record<string, unknown>;
    return new Response(JSON.stringify({ candidates: [{ content: { parts: [{ text: JSON.stringify(reply) }] }, finishReason: "STOP" }], usageMetadata: { promptTokenCount: 3, candidatesTokenCount: 2 }, ...extra }), { status: 200 });
  };
  return { client: geminiClient({ apiKey: "k", model: "gemini-2.0-flash", timeoutMs: 5000, fetchImpl }), captured: () => captured };
}

describe("geminiClient", () => {
  it("sends responseSchema without keywords Gemini rejects, returns validated data", async () => {
    const { client, captured } = fake({ a: 2 });
    const out = await client.generateJson({ name: "t", prompt: "p", schema, maxOutputTokens: 10 });
    expect(out.data).toEqual({ a: 2 });
    expect(out.tokens).toEqual({ input: 3, output: 2 });
    const cfg = (captured()!.generationConfig as Record<string, unknown>);
    expect(cfg.responseMimeType).toBe("application/json");
    expect(JSON.stringify(cfg.responseSchema)).not.toMatch(/additionalProperties|\$schema/);
  });
  it("safety block → failed-precondition reason:safety", async () => {
    const { client } = fake({ a: 1 }, { promptFeedback: { blockReason: "SAFETY" } });
    await expect(client.generateJson({ name: "t", prompt: "p", schema, maxOutputTokens: 10 })).rejects.toMatchObject({ code: "failed-precondition", details: { reason: "safety" } });
  });
  it("schema mismatch → unavailable", async () => {
    const { client } = fake({ a: "x" });
    await expect(client.generateJson({ name: "t", prompt: "p", schema, maxOutputTokens: 10 })).rejects.toMatchObject({ code: "unavailable" });
  });
});

describe("vendor selection", () => {
  it("defaults to openai, accepts gemini case-insensitively", () => {
    expect(parseVendor(undefined)).toBe("openai");
    expect(parseVendor("GEMINI ")).toBe("gemini");
    expect(parseVendor("grok")).toBe("openai"); // v1's Grok adapter is gone on purpose
  });
  it("makeLlm builds the right client", () => {
    expect(makeLlm("gemini", { apiKey: "k", model: "m", timeoutMs: 1 }).vendor).toBe("gemini");
    expect(makeLlm("openai", { apiKey: "k", model: "m", timeoutMs: 1 }).vendor).toBe("openai");
  });
});

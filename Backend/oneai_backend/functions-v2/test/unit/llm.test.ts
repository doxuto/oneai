import { describe, expect, it } from "vitest";
import { z } from "zod";
import { openAiClient } from "../../src/lib/llm/openai.js";
import { fill } from "../../src/prompts/summarize.js";
import { SummarizeOutput, summarizeTranscript, trimTranscript } from "../../src/ai/summarize.js";
import type { LlmClient } from "../../src/lib/llm/types.js";

const good = {
  contentKind: "team_meeting", title: "Standup", text: "We synced.", iconEmoji: "📝",
  sections: [{ title: "Overview", bullets: ["• We synced."] }], calendarEvents: [],
};

function fakeOpenAi(reply: unknown, status = 200) {
  let captured: Record<string, unknown> | undefined;
  const fetchImpl: typeof fetch = async (_u, init) => {
    captured = JSON.parse(String(init?.body)) as Record<string, unknown>;
    const content = typeof reply === "string" ? reply : JSON.stringify(reply);
    return new Response(
      JSON.stringify({ model: "gpt-4o-mini-2024", choices: [{ message: { content }, finish_reason: "stop" }], usage: { prompt_tokens: 10, completion_tokens: 5 } }),
      { status },
    );
  };
  return { client: openAiClient({ apiKey: "k", model: "gpt-4o-mini", timeoutMs: 5000, fetchImpl }), captured: () => captured };
}

describe("fill", () => {
  it("substitutes every placeholder", () => expect(fill("a {{x}} b {{y}}", { x: "1", y: "2" })).toBe("a 1 b 2"));
  it("a missing variable is an error, never silently blank (v1 shipped a prompt with '${transcript}' literal)", () => {
    expect(() => fill("{{nope}}", {})).toThrow(/missing variable nope/);
  });
});

describe("trimTranscript", () => {
  it("leaves short text alone", () => expect(trimTranscript("abc", 10)).toBe("abc"));
  it("keeps head and tail and says how much was cut", () => {
    const t = trimTranscript("A".repeat(50) + "B".repeat(50), 20);
    expect(t.startsWith("AAAAAAAAAA")).toBe(true);
    expect(t.endsWith("BBBBBBBBBB")).toBe(true);
    expect(t).toMatch(/80 characters omitted/);
  });
});

describe("openAiClient.generateJson", () => {
  const schema = z.object({ a: z.number() });

  it("sends json_schema response_format and returns validated data + tokens", async () => {
    const { client, captured } = fakeOpenAi({ a: 1 });
    const out = await client.generateJson({ name: "t", prompt: "p", schema, maxOutputTokens: 10 });
    expect(out.data).toEqual({ a: 1 });
    expect(out.tokens).toEqual({ input: 10, output: 5 });
    const body = captured()!;
    expect((body.response_format as { type: string }).type).toBe("json_schema");
    expect(body.max_tokens).toBe(10);
  });

  it("schema mismatch is unavailable — never returned, so never cached", async () => {
    const { client } = fakeOpenAi({ a: "not a number" });
    await expect(client.generateJson({ name: "t", prompt: "p", schema, maxOutputTokens: 10 })).rejects.toMatchObject({ code: "unavailable" });
  });

  it("malformed JSON is unavailable", async () => {
    const { client } = fakeOpenAi("{not json");
    await expect(client.generateJson({ name: "t", prompt: "p", schema, maxOutputTokens: 10 })).rejects.toMatchObject({ code: "unavailable" });
  });

  it("a refusal is failed-precondition with reason:safety", async () => {
    const fetchImpl: typeof fetch = async () =>
      new Response(JSON.stringify({ choices: [{ message: { refusal: "no" } }] }), { status: 200 });
    const client = openAiClient({ apiKey: "k", model: "m", timeoutMs: 5000, fetchImpl });
    await expect(client.generateJson({ name: "t", prompt: "p", schema, maxOutputTokens: 10 })).rejects.toMatchObject({
      code: "failed-precondition", details: { reason: "safety" },
    });
  });

  it("429 → resource-exhausted", async () => {
    const fetchImpl: typeof fetch = async () => new Response("rate", { status: 429 });
    const client = openAiClient({ apiKey: "k", model: "m", timeoutMs: 5000, fetchImpl });
    await expect(client.generateJson({ name: "t", prompt: "p", schema, maxOutputTokens: 10 })).rejects.toMatchObject({ code: "resource-exhausted" });
  });
});

describe("summarizeTranscript", () => {
  it("fills the prompt, validates the reply and maps to Summary", async () => {
    let seenPrompt = "";
    const llm: LlmClient = {
      vendor: "openai",
      async generateJson(req) {
        seenPrompt = req.prompt;
        return { data: SummarizeOutput.parse(good) as never, model: "m", tokens: { input: 1, output: 1 } };
      },
    };
    const out = await summarizeTranscript(llm, {
      transcript: "hello team", summaryLanguage: "vi", description: "weekly", now: new Date("2026-09-23T03:00:00Z"), timezone: "Asia/Ho_Chi_Minh",
    });
    expect(out.summary).toEqual({ title: "Standup", text: "We synced.", icon: "📝", sections: good.sections });
    expect(out.contentKind).toBe("team_meeting");
    expect(seenPrompt).toContain("hello team");
    expect(seenPrompt).toContain("Asia/Ho_Chi_Minh");
    expect(seenPrompt).toContain("summary language: vi");
    expect(seenPrompt).not.toContain("{{");
  });
});

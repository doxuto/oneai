import { describe, expect, it } from "vitest";
import { cosine, EMBED_BATCH_MAX, EMBED_MAX_CHARS, geminiEmbedder, openAiEmbedder } from "../../src/lib/llm/embeddings.js";

function fakeFetch(reply: unknown, status = 200) {
  let captured: Record<string, unknown> | undefined;
  let url = "";
  const fetchImpl: typeof fetch = async (u, init) => {
    url = String(u);
    captured = JSON.parse(String(init?.body)) as Record<string, unknown>;
    return new Response(JSON.stringify(reply), { status });
  };
  return { fetchImpl, captured: () => captured, url: () => url };
}

describe("embedders (S11-01)", () => {
  it("gemini: batchEmbedContents with task type + outputDimensionality, one vector per input", async () => {
    const f = fakeFetch({ embeddings: [{ values: [1, 0, 0] }, { values: [0, 1, 0] }] });
    const e = geminiEmbedder({ apiKey: "k", model: "gemini-embedding-001", dimension: 3, timeoutMs: 1000, fetchImpl: f.fetchImpl });
    const out = await e.embed(["a", "b"], "query");
    expect(out).toEqual([[1, 0, 0], [0, 1, 0]]);
    const reqs = f.captured()!.requests as { taskType: string; outputDimensionality: number; model: string }[];
    expect(reqs[0]).toMatchObject({ taskType: "RETRIEVAL_QUERY", outputDimensionality: 3, model: "models/gemini-embedding-001" });
    expect(f.url()).toContain("batchEmbedContents?key=k");
    await e.embed(["x", "y"], "document");
    expect((f.captured()!.requests as { taskType: string }[])[0]?.taskType).toBe("RETRIEVAL_DOCUMENT");
  });

  it("openai: dimensions param, rows re-ordered by index", async () => {
    const f = fakeFetch({ data: [{ index: 1, embedding: [0, 1] }, { index: 0, embedding: [1, 0] }] });
    const e = openAiEmbedder({ apiKey: "k", model: "text-embedding-3-small", dimension: 2, timeoutMs: 1000, fetchImpl: f.fetchImpl });
    expect(await e.embed(["a", "b"], "document")).toEqual([[1, 0], [0, 1]]);
    expect(f.captured()).toMatchObject({ dimensions: 2, input: ["a", "b"] });
  });

  it("wrong width or count is an error, empty input is free", async () => {
    const f = fakeFetch({ data: [{ index: 0, embedding: [1, 0, 0] }] });
    const e = openAiEmbedder({ apiKey: "k", model: "m", dimension: 2, timeoutMs: 1000, fetchImpl: f.fetchImpl });
    await expect(e.embed(["a"], "document")).rejects.toThrow(/expected 2 dims/);
    await expect(e.embed(["a", "b"], "document")).rejects.toThrow(/vectors for 2 inputs/);
    expect(await e.embed([], "document")).toEqual([]);
  });

  it("clips long inputs and maps 429 to resource-exhausted", async () => {
    const f = fakeFetch({ data: [{ index: 0, embedding: [1, 0] }] });
    const e = openAiEmbedder({ apiKey: "k", model: "m", dimension: 2, timeoutMs: 1000, fetchImpl: f.fetchImpl });
    await e.embed(["x".repeat(EMBED_MAX_CHARS + 100)], "document");
    expect(((f.captured()!.input as string[])[0] ?? "").length).toBe(EMBED_MAX_CHARS);
    const busy = fakeFetch({}, 429);
    const e2 = openAiEmbedder({ apiKey: "k", model: "m", dimension: 2, timeoutMs: 1000, fetchImpl: busy.fetchImpl });
    await expect(e2.embed(["a"], "query")).rejects.toMatchObject({ code: "resource-exhausted" });
  });

  it("cosine", () => {
    expect(cosine([1, 0], [1, 0])).toBeCloseTo(1);
    expect(cosine([1, 0], [0, 1])).toBeCloseTo(0);
    expect(cosine([0, 0], [1, 1])).toBe(0);
  });

  it("S11-01b: more than 100 inputs go out in ordered batches of ≤100 (Gemini's cap), vectors joined in order", async () => {
    const sizes: number[] = [];
    const fetchImpl: typeof fetch = async (_u, init) => {
      const body = JSON.parse(String(init?.body)) as { requests: { content: { parts: { text: string }[] } }[] };
      sizes.push(body.requests.length);
      return new Response(JSON.stringify({ embeddings: body.requests.map((r) => ({ values: [Number(r.content.parts[0]!.text), 0] })) }));
    };
    const e = geminiEmbedder({ apiKey: "k", model: "m", dimension: 2, timeoutMs: 1000, fetchImpl });
    const texts = Array.from({ length: 205 }, (_, i) => String(i));
    const out = await e.embed(texts, "document");
    expect(sizes).toEqual([EMBED_BATCH_MAX, EMBED_BATCH_MAX, 5]);
    expect(out.map((v) => v[0])).toEqual(texts.map(Number));
  });
});


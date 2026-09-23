/**
 * Text embeddings for S11-01/02 (ask across notes, semantic search).
 * One vector per note, dimension fixed by EMBEDDING_DIM so Firestore's vector
 * index (firestore.indexes.json) and the stored vectors always agree.
 */
import { mapProviderError } from "../errors.js";
import { log } from "../logging.js";

export type EmbedTask = "document" | "query";

export interface Embedder {
  readonly vendor: "openai" | "gemini";
  readonly dimension: number;
  /** One vector per input, same order. Empty input → []. */
  embed(texts: string[], task: EmbedTask, signal?: AbortSignal): Promise<number[][]>;
}

export interface EmbedderOptions {
  apiKey: string;
  model: string;
  dimension: number;
  timeoutMs: number;
  fetchImpl?: typeof fetch;
  endpoint?: string;
}

/** Inputs longer than this are cut — the models cap at ~2k tokens and the tail of a note adds little. */
export const EMBED_MAX_CHARS = 8000;

function clip(texts: string[]): string[] {
  return texts.map((t) => (t.length > EMBED_MAX_CHARS ? t.slice(0, EMBED_MAX_CHARS) : t));
}

function checkDims(vectors: number[][], dimension: number, vendor: string): number[][] {
  for (const v of vectors) {
    if (v.length !== dimension) throw new Error(`${vendor} embedding: expected ${dimension} dims, got ${v.length}`);
  }
  return vectors;
}

async function post(fetchImpl: typeof fetch, url: string, init: RequestInit, timeoutMs: number, vendor: string, outer?: AbortSignal): Promise<unknown> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(new Error("embed timeout")), timeoutMs);
  outer?.addEventListener("abort", () => ctrl.abort(outer.reason));
  let res: Response;
  try {
    res = await fetchImpl(url, { ...init, signal: ctrl.signal });
  } catch (err) {
    throw mapProviderError(vendor, undefined, err);
  } finally {
    clearTimeout(timer);
  }
  if (!res.ok) {
    log.warn(`${vendor}.embed_error`, { status: res.status });
    throw mapProviderError(vendor, res.status, new Error(await res.text()));
  }
  return res.json();
}

/** Gemini `gemini-embedding-001` (or text-embedding-004) via batchEmbedContents. */
export function geminiEmbedder(opts: EmbedderOptions): Embedder {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const endpoint = opts.endpoint ?? `https://generativelanguage.googleapis.com/v1beta/models/${opts.model}:batchEmbedContents`;
  return {
    vendor: "gemini",
    dimension: opts.dimension,
    async embed(texts, task, signal) {
      if (texts.length === 0) return [];
      const body = {
        requests: clip(texts).map((text) => ({
          model: `models/${opts.model}`,
          content: { parts: [{ text }] },
          taskType: task === "query" ? "RETRIEVAL_QUERY" : "RETRIEVAL_DOCUMENT",
          outputDimensionality: opts.dimension,
        })),
      };
      const json = (await post(fetchImpl, `${endpoint}?key=${encodeURIComponent(opts.apiKey)}`,
        { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body) }, opts.timeoutMs, "gemini", signal)) as
        { embeddings?: { values?: number[] }[] };
      const vectors = (json.embeddings ?? []).map((e) => e.values ?? []);
      if (vectors.length !== texts.length) throw new Error(`gemini embedding: ${vectors.length} vectors for ${texts.length} inputs`);
      return checkDims(vectors, opts.dimension, "gemini");
    },
  };
}

/** OpenAI `text-embedding-3-small` with `dimensions` set so both vendors store the same width. */
export function openAiEmbedder(opts: EmbedderOptions): Embedder {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const endpoint = opts.endpoint ?? "https://api.openai.com/v1/embeddings";
  return {
    vendor: "openai",
    dimension: opts.dimension,
    async embed(texts, _task, signal) {
      if (texts.length === 0) return [];
      const json = (await post(fetchImpl, endpoint, {
        method: "POST",
        headers: { "content-type": "application/json", authorization: `Bearer ${opts.apiKey}` },
        body: JSON.stringify({ model: opts.model, input: clip(texts), dimensions: opts.dimension }),
      }, opts.timeoutMs, "openai", signal)) as { data?: { index?: number; embedding?: number[] }[] };
      const rows = [...(json.data ?? [])].sort((a, b) => (a.index ?? 0) - (b.index ?? 0));
      const vectors = rows.map((r) => r.embedding ?? []);
      if (vectors.length !== texts.length) throw new Error(`openai embedding: ${vectors.length} vectors for ${texts.length} inputs`);
      return checkDims(vectors, opts.dimension, "openai");
    },
  };
}

/** Cosine similarity for tests and for re-ranking small candidate sets. */
export function cosine(a: number[], b: number[]): number {
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length; i++) { dot += (a[i] ?? 0) * (b[i] ?? 0); na += (a[i] ?? 0) ** 2; nb += (b[i] ?? 0) ** 2; }
  return na === 0 || nb === 0 ? 0 : dot / Math.sqrt(na * nb);
}

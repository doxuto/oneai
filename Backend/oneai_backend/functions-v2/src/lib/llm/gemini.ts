import { HttpsError } from "firebase-functions/v2/https";
import { zodToJsonSchema } from "zod-to-json-schema";
import { mapProviderError } from "../errors.js";
import { log } from "../logging.js";
import { sseData } from "./sse.js";
import type { GenerateJsonRequest, GenerateJsonResult, LlmClient, StreamTextRequest, StreamTextResult } from "./types.js";

export interface GeminiOptions {
  apiKey: string;
  model: string;
  timeoutMs: number;
  fetchImpl?: typeof fetch;
  endpoint?: string;
}

interface GeminiReply {
  candidates?: { content?: { parts?: { text?: string }[] }; finishReason?: string }[];
  promptFeedback?: { blockReason?: string };
  usageMetadata?: { promptTokenCount?: number; candidatesTokenCount?: number };
}

/** Strip the JSON-schema keywords Gemini's responseSchema does not accept. */
function geminiSchema(input: unknown): unknown {
  if (Array.isArray(input)) return input.map(geminiSchema);
  if (!input || typeof input !== "object") return input;
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(input as Record<string, unknown>)) {
    if (["$schema", "additionalProperties", "$ref", "definitions", "default", "title"].includes(k)) continue;
    out[k] = geminiSchema(v);
  }
  return out;
}

export function geminiClient(opts: GeminiOptions): LlmClient {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const endpoint = opts.endpoint ?? `https://generativelanguage.googleapis.com/v1beta/models/${opts.model}:generateContent`;

  return {
    vendor: "gemini",
    async generateJson<T>(req: GenerateJsonRequest<T>, outerSignal?: AbortSignal): Promise<GenerateJsonResult<T>> {
      const schema = geminiSchema(zodToJsonSchema(req.schema, { $refStrategy: "none" }));
      const body = {
        ...(req.system ? { systemInstruction: { parts: [{ text: req.system }] } } : {}),
        contents: [{ role: "user", parts: [{ text: req.prompt }] }],
        generationConfig: {
          temperature: req.temperature ?? 0.2,
          maxOutputTokens: req.maxOutputTokens,
          responseMimeType: "application/json",
          responseSchema: schema,
        },
      };
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(new Error("llm timeout")), opts.timeoutMs);
      outerSignal?.addEventListener("abort", () => ctrl.abort(outerSignal.reason));
      const startedAt = Date.now();

      let res: Response;
      try {
        res = await fetchImpl(`${endpoint}?key=${encodeURIComponent(opts.apiKey)}`, {
          method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body), signal: ctrl.signal,
        });
      } catch (err) {
        clearTimeout(timer);
        if (ctrl.signal.aborted) throw new HttpsError("deadline-exceeded", "The model took too long");
        throw mapProviderError("gemini", undefined, err);
      }
      clearTimeout(timer);
      if (!res.ok) {
        const text = (await res.text().catch(() => "")).slice(0, 300);
        throw mapProviderError("gemini", res.status, new Error(text), { name: req.name });
      }
      const json = (await res.json()) as GeminiReply;
      const tokens = { input: json.usageMetadata?.promptTokenCount ?? 0, output: json.usageMetadata?.candidatesTokenCount ?? 0 };
      log.info("gemini.done", { name: req.name, model: opts.model, ms: Date.now() - startedAt, ...tokens, finish: json.candidates?.[0]?.finishReason ?? null });

      if (json.promptFeedback?.blockReason || json.candidates?.[0]?.finishReason === "SAFETY") {
        throw new HttpsError("failed-precondition", "The model declined this content", { reason: "safety" });
      }
      const text = json.candidates?.[0]?.content?.parts?.map((p) => p.text ?? "").join("") ?? "";
      if (!text) throw new HttpsError("unavailable", "Empty model response");
      let parsed: unknown;
      try { parsed = JSON.parse(text); } catch {
        log.warn("gemini.bad_json", { name: req.name, head: text.slice(0, 120) });
        throw new HttpsError("unavailable", "Model returned malformed output");
      }
      const checked = req.schema.safeParse(parsed);
      if (!checked.success) {
        log.warn("gemini.schema_mismatch", { name: req.name, issues: checked.error.issues.length });
        throw new HttpsError("unavailable", "Model output did not match the expected shape");
      }
      return { data: checked.data, model: opts.model, tokens };
    },

    async streamText(req: StreamTextRequest, onDelta: (d: string) => void, outerSignal?: AbortSignal): Promise<StreamTextResult> {
      const streamEndpoint = endpoint.replace(":generateContent", ":streamGenerateContent");
      const body = {
        ...(req.system ? { systemInstruction: { parts: [{ text: req.system }] } } : {}),
        contents: [
          ...(req.history ?? []).map((t) => ({ role: t.role === "assistant" ? "model" : "user", parts: [{ text: t.text }] })),
          { role: "user", parts: [{ text: req.prompt }] },
        ],
        generationConfig: { temperature: req.temperature ?? 0.3, maxOutputTokens: req.maxOutputTokens },
      };
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(new Error("llm timeout")), opts.timeoutMs);
      outerSignal?.addEventListener("abort", () => ctrl.abort(outerSignal.reason));
      const startedAt = Date.now();
      let res: Response;
      try {
        res = await fetchImpl(`${streamEndpoint}?alt=sse&key=${encodeURIComponent(opts.apiKey)}`, {
          method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(body), signal: ctrl.signal,
        });
      } catch (err) {
        clearTimeout(timer);
        if (ctrl.signal.aborted) throw new HttpsError("deadline-exceeded", "The model took too long");
        throw mapProviderError("gemini", undefined, err);
      }
      if (!res.ok || !res.body) {
        clearTimeout(timer);
        const text = (await res.text().catch(() => "")).slice(0, 300);
        throw mapProviderError("gemini", res.status, new Error(text), { name: req.name });
      }
      let text = "";
      const tokens = { input: 0, output: 0 };
      try {
        for await (const data of sseData(res.body)) {
          let ev: GeminiReply;
          try { ev = JSON.parse(data); } catch { continue; }
          if (ev.promptFeedback?.blockReason || ev.candidates?.[0]?.finishReason === "SAFETY") {
            throw new HttpsError("failed-precondition", "The model declined this content", { reason: "safety" });
          }
          if (ev.usageMetadata) { tokens.input = ev.usageMetadata.promptTokenCount ?? 0; tokens.output = ev.usageMetadata.candidatesTokenCount ?? 0; }
          const delta = ev.candidates?.[0]?.content?.parts?.map((p) => p.text ?? "").join("") ?? "";
          if (delta) { text += delta; onDelta(delta); }
        }
      } catch (err) {
        if (err instanceof HttpsError) throw err;
        if (ctrl.signal.aborted) throw new HttpsError("deadline-exceeded", "The model took too long");
        throw mapProviderError("gemini", undefined, err, { name: req.name, phase: "stream" });
      } finally {
        clearTimeout(timer);
      }
      log.info("gemini.stream_done", { name: req.name, model: opts.model, ms: Date.now() - startedAt, ...tokens, chars: text.length });
      if (text.length === 0) throw new HttpsError("unavailable", "Empty model response");
      return { text, model: opts.model, tokens };
    },
  };
}

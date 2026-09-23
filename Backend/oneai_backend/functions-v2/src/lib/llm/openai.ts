import { HttpsError } from "firebase-functions/v2/https";
import { zodToJsonSchema } from "zod-to-json-schema";
import { mapProviderError } from "../errors.js";
import { log } from "../logging.js";
import { sseData } from "./sse.js";
import type { GenerateJsonRequest, GenerateJsonResult, LlmClient, StreamTextRequest, StreamTextResult } from "./types.js";

export interface OpenAiOptions {
  apiKey: string;
  model: string;
  timeoutMs: number;
  fetchImpl?: typeof fetch;
  endpoint?: string;
}

interface ChatCompletion {
  model?: string;
  choices?: { message?: { content?: string | null; refusal?: string | null }; finish_reason?: string }[];
  usage?: { prompt_tokens?: number; completion_tokens?: number };
}

/**
 * OpenAI chat completions with strict JSON-schema output. The zod schema is
 * the source of truth: it becomes the response_format AND validates the
 * reply, so a model that drifts fails loudly instead of being cached.
 */
export function openAiClient(opts: OpenAiOptions): LlmClient {
  const fetchImpl = opts.fetchImpl ?? fetch;
  const endpoint = opts.endpoint ?? "https://api.openai.com/v1/chat/completions";

  return {
    vendor: "openai",
    async generateJson<T>(req: GenerateJsonRequest<T>, outerSignal?: AbortSignal): Promise<GenerateJsonResult<T>> {
      const jsonSchema = zodToJsonSchema(req.schema, { name: req.name, $refStrategy: "none" });
      // zodToJsonSchema wraps in {$ref, definitions}; OpenAI wants the bare object.
      const bare = (jsonSchema as { definitions?: Record<string, unknown> }).definitions?.[req.name] ?? jsonSchema;

      const body = {
        model: opts.model,
        temperature: req.temperature ?? 0.2,
        max_tokens: req.maxOutputTokens,
        response_format: { type: "json_schema", json_schema: { name: req.name, schema: bare, strict: false } },
        messages: [
          ...(req.system ? [{ role: "system", content: req.system }] : []),
          { role: "user", content: req.prompt },
        ],
      };

      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(new Error("llm timeout")), opts.timeoutMs);
      outerSignal?.addEventListener("abort", () => ctrl.abort(outerSignal.reason));
      const startedAt = Date.now();

      let res: Response;
      try {
        res = await fetchImpl(endpoint, {
          method: "POST",
          headers: { "content-type": "application/json", authorization: `Bearer ${opts.apiKey}` },
          body: JSON.stringify(body),
          signal: ctrl.signal,
        });
      } catch (err) {
        clearTimeout(timer);
        if (ctrl.signal.aborted) throw new HttpsError("deadline-exceeded", "The model took too long");
        throw mapProviderError("openai", undefined, err);
      }
      clearTimeout(timer);

      if (!res.ok) {
        const text = (await res.text().catch(() => "")).slice(0, 300);
        throw mapProviderError("openai", res.status, new Error(text), { name: req.name });
      }

      const json = (await res.json()) as ChatCompletion;
      const choice = json.choices?.[0];
      const tokens = { input: json.usage?.prompt_tokens ?? 0, output: json.usage?.completion_tokens ?? 0 };
      log.info("openai.done", { name: req.name, model: json.model ?? opts.model, ms: Date.now() - startedAt, ...tokens, finish: choice?.finish_reason ?? null });

      if (choice?.message?.refusal) {
        throw new HttpsError("failed-precondition", "The model declined this content", { reason: "safety" });
      }
      const content = choice?.message?.content;
      if (typeof content !== "string" || content.length === 0) {
        throw new HttpsError("unavailable", "Empty model response");
      }

      let parsed: unknown;
      try {
        parsed = JSON.parse(content);
      } catch {
        log.warn("openai.bad_json", { name: req.name, head: content.slice(0, 120) });
        throw new HttpsError("unavailable", "Model returned malformed output");
      }
      const checked = req.schema.safeParse(parsed);
      if (!checked.success) {
        log.warn("openai.schema_mismatch", { name: req.name, issues: checked.error.issues.length });
        throw new HttpsError("unavailable", "Model output did not match the expected shape");
      }
      return { data: checked.data, model: json.model ?? opts.model, tokens };
    },

    async streamText(req: StreamTextRequest, onDelta: (d: string) => void, outerSignal?: AbortSignal): Promise<StreamTextResult> {
      const body = {
        model: opts.model,
        temperature: req.temperature ?? 0.3,
        max_tokens: req.maxOutputTokens,
        stream: true,
        stream_options: { include_usage: true },
        messages: [
          ...(req.system ? [{ role: "system", content: req.system }] : []),
          ...(req.history ?? []).map((t) => ({ role: t.role, content: t.text })),
          { role: "user", content: req.prompt },
        ],
      };
      const ctrl = new AbortController();
      const timer = setTimeout(() => ctrl.abort(new Error("llm timeout")), opts.timeoutMs);
      outerSignal?.addEventListener("abort", () => ctrl.abort(outerSignal.reason));
      const startedAt = Date.now();
      let res: Response;
      try {
        res = await fetchImpl(endpoint, {
          method: "POST",
          headers: { "content-type": "application/json", authorization: `Bearer ${opts.apiKey}` },
          body: JSON.stringify(body),
          signal: ctrl.signal,
        });
      } catch (err) {
        clearTimeout(timer);
        if (ctrl.signal.aborted) throw new HttpsError("deadline-exceeded", "The model took too long");
        throw mapProviderError("openai", undefined, err);
      }
      if (!res.ok || !res.body) {
        clearTimeout(timer);
        const text = (await res.text().catch(() => "")).slice(0, 300);
        throw mapProviderError("openai", res.status, new Error(text), { name: req.name });
      }
      let text = "";
      let model = opts.model;
      const tokens = { input: 0, output: 0 };
      try {
        for await (const data of sseData(res.body)) {
          if (data === "[DONE]") break;
          let ev: { model?: string; choices?: { delta?: { content?: string | null } }[]; usage?: { prompt_tokens?: number; completion_tokens?: number } };
          try { ev = JSON.parse(data); } catch { continue; }
          if (ev.model) model = ev.model;
          if (ev.usage) { tokens.input = ev.usage.prompt_tokens ?? 0; tokens.output = ev.usage.completion_tokens ?? 0; }
          const delta = ev.choices?.[0]?.delta?.content;
          if (typeof delta === "string" && delta.length > 0) { text += delta; onDelta(delta); }
        }
      } catch (err) {
        if (ctrl.signal.aborted) throw new HttpsError("deadline-exceeded", "The model took too long");
        throw mapProviderError("openai", undefined, err, { name: req.name, phase: "stream" });
      } finally {
        clearTimeout(timer);
      }
      log.info("openai.stream_done", { name: req.name, model, ms: Date.now() - startedAt, ...tokens, chars: text.length });
      if (text.length === 0) throw new HttpsError("unavailable", "Empty model response");
      return { text, model, tokens };
    },
  };
}

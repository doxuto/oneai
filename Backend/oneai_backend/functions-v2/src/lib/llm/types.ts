import type { ZodType, ZodTypeDef } from "zod";

export interface GenerateJsonRequest<T> {
  /** Stable name used for the JSON-schema response format and for logs. */
  name: string;
  system?: string;
  prompt: string;
  schema: ZodType<T, ZodTypeDef, unknown>;
  maxOutputTokens: number;
  temperature?: number;
}

export interface GenerateJsonResult<T> {
  data: T;
  model: string;
  tokens: { input: number; output: number };
}

export interface ChatTurn { role: "user" | "assistant"; text: string }

export interface StreamTextRequest {
  name: string;
  system?: string;
  /** Prior turns, oldest first. The final user message is `prompt`. */
  history?: ChatTurn[];
  prompt: string;
  maxOutputTokens: number;
  temperature?: number;
}

export interface StreamTextResult {
  text: string;
  model: string;
  tokens: { input: number; output: number };
}

export interface LlmClient {
  readonly vendor: "openai" | "gemini";
  generateJson<T>(req: GenerateJsonRequest<T>, signal?: AbortSignal): Promise<GenerateJsonResult<T>>;
  /** Streams deltas to onDelta as they arrive; resolves with the full text. */
  streamText(req: StreamTextRequest, onDelta: (delta: string) => void, signal?: AbortSignal): Promise<StreamTextResult>;
}

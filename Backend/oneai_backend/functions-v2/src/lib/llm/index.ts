export type { GenerateJsonRequest, GenerateJsonResult, LlmClient } from "./types.js";
export { openAiClient } from "./openai.js";
export { geminiClient } from "./gemini.js";

import { geminiClient } from "./gemini.js";
import { openAiClient } from "./openai.js";
import type { LlmClient } from "./types.js";

export type LlmVendor = "openai" | "gemini";

export function parseVendor(raw: string | undefined): LlmVendor {
  return raw?.trim().toLowerCase() === "gemini" ? "gemini" : "openai";
}

export function makeLlm(vendor: LlmVendor, opts: { apiKey: string; model: string; timeoutMs: number }): LlmClient {
  return vendor === "gemini" ? geminiClient(opts) : openAiClient(opts);
}

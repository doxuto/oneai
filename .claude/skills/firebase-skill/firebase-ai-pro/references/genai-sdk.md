# Google GenAI SDK (`@google/genai`)

One SDK, two backends. Everything below is the unified `@google/genai` package (1.x). The older `@google/generative-ai` package is deprecated and must not appear in new code.

## Setup — two modes

```ts
import { GoogleGenAI } from "@google/genai";
import { defineSecret, defineString } from "firebase-functions/params";

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
const GCP_PROJECT = defineString("GCLOUD_PROJECT");   // populated automatically in Cloud Functions

// Mode A — Gemini Developer API (API key from AI Studio). Simplest; billed to the key's project.
function devApi(): GoogleGenAI {
  return new GoogleGenAI({ apiKey: GEMINI_API_KEY.value() });    // inside the handler only
}

// Mode B — Vertex AI. No key: uses Application Default Credentials (the function's service account).
// Service account needs roles/aiplatform.user. Regional; data stays in `location`.
function vertex(): GoogleGenAI {
  return new GoogleGenAI({ vertexai: true, project: GCP_PROJECT.value(), location: "us-central1" });
}
```

| | Developer API | Vertex AI |
|---|---|---|
| Auth | API key (secret) | ADC, IAM |
| Files | `ai.files.upload` (48 h retention, ≤ 2 GB) | `fileData.fileUri = "gs://…"` from your bucket |
| Regions | global | pick `location`; `asia-southeast1` supports a subset of models — check the model list per region |
| Enterprise controls (VPC-SC, CMEK, data residency) | no | yes |
| Pick when | prototyping, small apps | production with GCS-backed documents, compliance needs |

Cache the client in a module-level `let ai: GoogleGenAI | undefined` and create on first use inside the handler. Do not create it at import time — `GEMINI_API_KEY.value()` is empty during deploy-time analysis.

## `generateContent`

```ts
import { GoogleGenAI, Type, HarmCategory, HarmBlockThreshold, FinishReason } from "@google/genai";

const res = await ai.models.generateContent({
  model: "gemini-2.5-flash",
  contents: [
    { role: "user", parts: [{ text: "Translate to Vietnamese:\n<doc>\n" + text + "\n</doc>" }] },
  ],
  config: {
    systemInstruction: "You are a precise translator. Output only the translation.",
    temperature: 0.2,
    topP: 0.95,
    maxOutputTokens: 2048,
    stopSequences: ["</end>"],
    candidateCount: 1,
    responseMimeType: "application/json",     // with responseSchema — see structured-output.md
    responseSchema: { type: Type.OBJECT, properties: { translation: { type: Type.STRING } }, required: ["translation"] },
    safetySettings: [
      { category: HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT, threshold: HarmBlockThreshold.BLOCK_ONLY_HIGH },
    ],
    thinkingConfig: { thinkingBudget: 0 },    // 2.5 Flash: disable thinking for cheap, deterministic tasks; Pro cannot disable
    abortSignal: AbortSignal.timeout(45_000),
    httpOptions: { timeout: 45_000 },         // ms; belt and braces with abortSignal
    labels: { feature: "translate" },         // Vertex only: shows up in billing export
  },
});
```

`contents` accepts, in increasing explicitness: a `string` (one user turn), a `Part[]`, a `Content`, or `Content[]` with `role: "user" | "model"` for multi-turn. Always use the explicit `Content[]` form in production code so the role and part boundaries are visible in review.

`systemInstruction` accepts a string or a `Content`. It is not part of `contents` and is not counted as a user turn — this is where the task definition goes; user data never goes here (see `prompting-and-safety.md`).

## Reading the response

```ts
const text = res.text;                         // getter: concatenated text parts of candidates[0]; undefined if none
const cand = res.candidates?.[0];
const finish = cand?.finishReason;             // FinishReason.STOP | MAX_TOKENS | SAFETY | RECITATION | OTHER | …
const blocked = res.promptFeedback?.blockReason;   // set when the *prompt* was blocked → candidates is empty
const usage = res.usageMetadata;
// usage.promptTokenCount, usage.candidatesTokenCount, usage.totalTokenCount,
// usage.thoughtsTokenCount (thinking models), usage.cachedContentTokenCount (context caching)
```

Handle in this order: `promptFeedback.blockReason` → `finishReason !== STOP` → parse `text`. Skipping the first two turns a safety block into a confusing `JSON.parse` error.

```ts
if (res.promptFeedback?.blockReason) throw new HttpsError("failed-precondition", "Request was blocked", { reason: res.promptFeedback.blockReason });
if (finish === FinishReason.SAFETY) throw new HttpsError("failed-precondition", "Response was blocked");
if (finish === FinishReason.MAX_TOKENS) throw new HttpsError("internal", "Response truncated — raise maxOutputTokens or shrink input");
```

## Multimodal input

Inline (≤ ~20 MB total request; use for resized images and small PDFs):

```ts
import { createUserContent, createPartFromBase64 } from "@google/genai";

const jpeg = await sharp(buffer).rotate().resize({ width: 1600, withoutEnlargement: true }).jpeg({ quality: 80 }).toBuffer();
const res = await ai.models.generateContent({
  model: "gemini-2.5-flash",
  contents: createUserContent([
    createPartFromBase64(jpeg.toString("base64"), "image/jpeg"),
    "Extract all text from this receipt. Preserve line order.",
  ]),
});
```

Equivalent explicit form: `{ inlineData: { mimeType: "image/jpeg", data: base64 } }`. Multiple pages = multiple parts in one user turn, in order, with a short text part between them ("Page 2:") when order matters.

By reference:

```ts
// Vertex AI: any GCS object the function's service account can read.
{ fileData: { fileUri: "gs://snaptool-prod.appspot.com/users/u1/scans/s1/page-1.jpg", mimeType: "image/jpeg" } }

// Developer API: upload first (temporary, 48 h), then reference.
import { createPartFromUri } from "@google/genai";
const file = await ai.files.upload({ file: "/tmp/scan.pdf", config: { mimeType: "application/pdf" } });
const part = createPartFromUri(file.uri!, file.mimeType!);
```

PDFs: pass `application/pdf` directly; the model reads text and layout per page (each page costs a fixed number of tokens — check the current pricing page). For scanned PDFs it does OCR itself. Cap pages (see `cost-and-limits.md`).

Supported inline mime types worth knowing: `image/jpeg`, `image/png`, `image/webp`, `image/heic` (convert HEIC with `sharp` anyway — it is the iOS default and support varies), `application/pdf`, `audio/*`, `video/*`.

## Streaming

```ts
const stream = await ai.models.generateContentStream({ model: "gemini-2.5-flash", contents, config });
let full = "";
for await (const chunk of stream) {
  const piece = chunk.text;                 // may be undefined for non-text chunks
  if (piece) { full += piece; response.sendChunk({ text: piece }); }
  // chunk.usageMetadata is populated on the final chunk(s); chunk.candidates[0].finishReason likewise
}
```

`generateContentStream` returns a promise of an async generator — `await` it before `for await`. Streaming and `responseSchema` combine, but the chunks are fragments of one JSON document; parse only the concatenation (see `streaming-to-ios.md` for the iOS contract).

## Other calls you will use

```ts
await ai.models.countTokens({ model: "gemini-2.5-flash", contents });   // → { totalTokens } — pre-flight for input caps
const chat = ai.chats.create({ model: "gemini-2.5-flash", history, config });   // multi-turn convenience; history: Content[]
const reply = await chat.sendMessage({ message: "…" });                           // or chat.sendMessageStream
const cache = await ai.caches.create({ model: "gemini-2.5-flash", config: { contents: bigDoc, systemInstruction, ttl: "3600s" } });
await ai.models.generateContent({ model: "gemini-2.5-flash", contents: q, config: { cachedContent: cache.name } });
```

Chat history for an iOS app is stored in Firestore, not in the function's memory — functions are stateless; rebuild `history` from the conversation document on each call and cap it.

## Errors

The SDK throws `ApiError` (exported from `@google/genai`; has `status: number` and `message`) for HTTP failures — verify the exact class name against the installed SDK version if it does not import. Map:

| Status | Meaning | HttpsError |
|---|---|---|
| 400 | bad request (schema, mime, oversized) | `invalid-argument` (bug — log with details) |
| 401 / 403 | key / IAM | `internal` (alert; never expose) |
| 404 | model name wrong or not in region | `internal` |
| 429 | rate or quota | `resource-exhausted`; retry once with backoff for interactive, let Cloud Tasks retry for workers |
| 500 / 503 | model side | `unavailable`; retry with backoff |
| `AbortError` / timeout | your `abortSignal` fired | `deadline-exceeded` |

```ts
import { ApiError } from "@google/genai";
try { … } catch (e: unknown) {
  if (e instanceof ApiError) {
    logger.error("gemini api error", { status: e.status, message: e.message, feature });
    if (e.status === 429) throw new HttpsError("resource-exhausted", "AI service busy, try again");
    if (e.status >= 500) throw new HttpsError("unavailable", "AI service unavailable");
    throw new HttpsError("internal", "AI request failed");
  }
  if ((e as Error).name === "AbortError" || (e as Error).name === "TimeoutError") throw new HttpsError("deadline-exceeded", "AI request timed out");
  throw e;
}
```

## Model naming

- Default: `gemini-2.5-flash`. Cheaper: `gemini-2.5-flash-lite`. Stronger: `gemini-2.5-pro`. Names and availability change several times a year — **check the current model list** (`ai.models.list()` or the docs) before pinning, and keep the name in one constant per feature.
- Do not use `-latest` or preview aliases in production; they change behaviour under you.
- Vertex model ids are the same strings, but regional availability differs from the Developer API.

## Does not exist / common mistakes

- `import { GoogleGenerativeAI } from "@google/generative-ai"` and `genAI.getGenerativeModel({ model })` — the deprecated SDK. Replace with `GoogleGenAI` + `ai.models.generateContent`.
- `model.generateContent(prompt)` — there is no model object in `@google/genai`; the model is a string argument.
- `res.response.text()` — old SDK shape. New: `res.text` (a getter, not a function).
- `generationConfig: { … }` — the key is `config`.
- `config.systemInstruction` inside `contents` as `role: "system"` — Gemini has no system role in `contents`; use `config.systemInstruction`.
- `for await (const chunk of ai.models.generateContentStream(...))` without `await` on the call — it returns a promise.
- Sending `inlineData.data` as a `Buffer` — must be a base64 string.
- `responseSchema` with `$ref`, `additionalProperties`, or `oneOf` — not supported by the OpenAPI-subset schema; see `structured-output.md`.
- Assuming `usageMetadata` is on every streamed chunk — only the last one(s).
- `new GoogleGenAI({ apiKey })` with `vertexai: true` and expecting ADC — with an API key on Vertex you are in express mode; for production Vertex, omit the key.

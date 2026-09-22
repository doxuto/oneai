import fs from "node:fs/promises";
import path from "node:path";
import { getProvider } from "../utils/llm/index.js";

const provider = getProvider();
const OpenAIProvider = getProvider("openai")
const GerminiProvider = getProvider("gemini")
const PROMPT_DIR = path.resolve("utils", "prompts");

async function loadPrompt(fileName) {
  return fs.readFile(path.join(PROMPT_DIR, fileName), "utf8");
}


function stripCodeFence(text) {
  return text.replace(/```json|```/g, "").trim();
}

/**
 * Generate structured JSON summary (incl. mindmap, quiz, flashcards) from transcript
 *
 * @param {string} transcript – raw transcript text
 * @param {string} summaryLanguage – language code (e.g., "en", "vi")
 * @param {string} [description=""] – additional context (optional)
 * @param {string} [timezone="GMT-7"] – timezone for resolving relative dates
 * @param {number} [temperature=0.6] – generation temperature
 * @param {string} [providerId="openai"] – LLM provider ("openai", "gemini", "grok")
 * @param {string} [model] – override default model
 * @returns {Promise<string>} – JSON structured summary
 **/

export async function summarizeFromTranscript(
  transcript,
  summaryLanguage,
  description = "",
  timezone = "GMT-7",
  temperature = 0.6
) {
  const now = new Date().toISOString();
  let basePrompt = await loadPrompt("summarizeFromTranscript.txt");

  const prompt = basePrompt
    .replace("${summaryLanguage}", summaryLanguage)
    .replace("${now}", now)
    .replace("${timezone}", timezone)
    .replace("${transcript}", transcript)
    .replace("${description}", description ? `\n\nAdditional context: ${description}` : "");

  const providerId = "openai";
  const modelId = "gpt-4o";

  let output = await OpenAIProvider.generate({ prompt, temperature, modelId });
  return stripCodeFence(output);
}


/**
 * Generate structured JSON summary (incl. mindmap, quiz, flashcards) from transcript
 *
 * @param {string} text – raw text
 * @param {string} summaryLanguage – language code (e.g., "en", "vi")
 * @param {string} [description=""] – additional context (optional)
 * @param {string} [timezone="GMT-7"] – timezone for resolving relative dates
 * @param {number} [temperature=0.6] – generation temperature
 * @param {string} [providerId="openai"] – LLM provider ("openai", "gemini", "grok")
 * @param {string} [model] – override default model
 * @returns {Promise<string>} – JSON structured summary
 **/

export async function summarizeFromText(
  text,
  summaryLanguage,
  description = "",
  timezone = "GMT-7",
  temperature = 0.6
) {
  const now = new Date().toISOString();
  let basePrompt = await loadPrompt("summarizeFromTranscript.txt");

  const prompt = basePrompt
    .replace("${summaryLanguage}", summaryLanguage)
    .replace("${now}", now)
    .replace("${timezone}", timezone)
    .replace("${text}", text)
    .replace("${description}", description ? `\n\nAdditional context: ${description}` : "");

  const providerId = "openai";
  const modelId = "gpt-4o";

  let output = await OpenAIProvider.generate({ prompt, temperature, modelId });
  return stripCodeFence(output);
}

/* ------------------------------------------------------------------ */
/* 🚀 2. Generate Short Questions                                     */
/* ------------------------------------------------------------------ */

export async function generateShortQuestions(transcription, languageCode = "en") {
  const basePrompt = await loadPrompt("shortQuestions.txt");      // tạo file txt tương ứng
  const prompt = basePrompt
    .replace("${languageCode}", languageCode)
    .replace("${transcription}", transcription);

  const raw = await provider.generate({ prompt, temperature: 0.4 });
  try {
    return JSON.parse(stripCodeFence(raw));
  } catch {
    return { short_questions: [] };
  }
}

/* ------------------------------------------------------------------ */
/* 🚀 3. Answer Question from Summary                                 */
/* ------------------------------------------------------------------ */

export async function answerQuestionFromSummary(transcription, question) {
  const basePrompt = await loadPrompt("answerFromSummary.txt");   // tạo file
  const prompt = basePrompt
    .replace("${transcription}", transcription)
    .replace("${question}", question);

  return stripCodeFence(await provider.generate({ prompt, temperature: 0.5 }));
}

/* ------------------------------------------------------------------ */
/* 🚀 4. Flashcards                                                   */
/* ------------------------------------------------------------------ */

export async function generateFlashcards(transcript, languageCode = "en") {
  const basePrompt = await loadPrompt("flashcards.txt");
  const prompt = basePrompt
    .replace("${languageCode}", languageCode)
    .replace("${transcript}", transcript);

  try {
    const raw = await provider.generate({ prompt, temperature: 0.5 });
    return JSON.parse(stripCodeFence(raw));
  } catch {
    return { flashcards: [] };
  }
}

/* ------------------------------------------------------------------ */
/* 🚀 5. Quiz                                                         */
/* ------------------------------------------------------------------ */

export async function generateQuiz(transcript, languageCode = "en") {
  const basePrompt = await loadPrompt("quiz.txt");
  const prompt = basePrompt
    .replace("${languageCode}", languageCode)
    .replace("${transcript}", transcript);

  try {
    const raw = await provider.generate({ prompt, temperature: 0.5 });
    return JSON.parse(stripCodeFence(raw));
  } catch {
    return { quiz: [] };
  }
}

/* ------------------------------------------------------------------ */
/* 🚀 6. Mind-map                                                     */
/* ------------------------------------------------------------------ */

export async function generateMindMap(transcript, languageCode = "en") {
  const basePrompt = await loadPrompt("mindmap.txt");
  const prompt = basePrompt
    .replace("${languageCode}", languageCode)
    .replace("${transcript}", transcript);

  try {
    const raw = await provider.generate({ prompt, temperature: 0.4 });
    return JSON.parse(stripCodeFence(raw));
  } catch {
    return { mindmap: { title: "Untitled", children: [] } };
  }
}

/* ------------------------------------------------------------------ */
/* 🚀 7. Speaker Mapping                                              */
/* ------------------------------------------------------------------ */

/**
 * Generate speaker mapping from transcript
 * @param {string} transcript – full raw transcript text
 * @param {string} [providerId="openai"]
 * @param {string} [modelId="gpt-4o"]
 * @param {number} [temperature=0.2]
 * @returns {Promise<Object>} – { speaker_0: "Name", ... }
 **/
export async function mapSpeakers(
  transcript
) {
  const basePrompt = await loadPrompt("mapSpeakers.txt");
  const prompt = basePrompt.replace("${transcript}", transcript);
  const modelId = "gpt-4o";
  const providerId = "openai";
  try {
    const raw = await getProvider(providerId).generate({
      prompt,
      model: modelId,
    });
    return JSON.parse(stripCodeFence(raw));
  } catch (err) {
    console.error("🔥 [mapSpeakers] Error parsing JSON:", err);
    return {};
  }
}
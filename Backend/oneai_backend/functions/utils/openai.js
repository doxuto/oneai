// require("dotenv").config();

// const OpenAI = require("openai");
// const client = new OpenAI({
//   apiKey: process.env.OPENAI_API_KEY
// });

// /**
//  * Summarize raw transcript into structured summary JSON
//  * @param {string} transcript - The full transcript text (raw)
//  * @param {string} summaryLanguage - e.g., "en", "vi", "en-US"
//  * @param {string} [description] - Optional context to help summarization
//  * @param {string} [timezone] - Optional timezone
//  * @param {number} [temperature=0.6] - Optional temperature for OpenAI generation
//  * @returns {Promise<string>} JSON string of structured summary
//  */
// exports.summarizeText = async (transcript, summaryLanguage, description = "", timezone = "GMT -7", temperature = 0.6) => {
//   const now = new Date().toISOString();
//   const prompt = `You are a world-class summarizer and content architect.

// You are given a raw transcript from a spoken session. Your task is to analyze the content deeply and return a rich, clear, structured summary in strict JSON format.

// Your job:
// 	•	Classify the conversation into one of the following session types:
// “interview”, “podcast”, “team_meeting”, “lecture”, “presentation”, “webinar”, “casual_talk”.
// If the session type is unclear, return “other”.
// 	•	Create a concise, informative title in ${summaryLanguage}.
// 	•	Extract all meaningful ideas and insights and organize them into titled sections with well-written bullet points:
// 	•	Each section must have a clear title and an array of bullet points.
// 	•	Use nested sub-bullets where appropriate.
// 	•	Do not summarize vague impressions. Only extract what is explicitly stated.
// 	•	Add an emoji icon that reflects the tone or subject of the session (e.g. 🎤, 💼, 🧠, 📚, 🚀).
// 	•	Strict Speaker Mapping Rules — DO NOT GUESS NAMES
// 	1.	Detect speaker names only if they are explicitly mentioned in the transcript, such as:
// 	•	“Hi, I’m Alice”
// 	•	“Thanks Brian”
// 	•	“Okay Cindy, go ahead”
// 	2.	A speaker ID can only be mapped to a name if there is clear, unambiguous textual evidence linking that name to the speaker.
// 	3.	If a name is mentioned but cannot be confidently linked to a specific speaker ID, do not assign it.
// 	4.	If no proper name is found for a speaker, leave the speaker ID unmapped (e.g. “speaker_2”: “speaker_2”).
// 	5.	Do NOT invent names, roles, or labels for speakers. Absolutely no creative assumptions.
// 	•	Detect Mentioned Meetings or Appointments
// For each meeting mentioned in the transcript:
// 	•	Extract the appointment and create a calendarEvents entry with:
// 	•	“id” (a unique string)
// 	•	“title” (brief, clear)
// 	•	“description” (short summary of what the meeting is about)
// 	•	“datetime” (absolute ISO-8601 time, resolve relative times like “tomorrow at 2 PM” using current time ${now} in timezone ${timezone})
// 	•	“participants” (names or groups mentioned)
// 	•	“rawText” (the original phrase from the transcript)

// Return your result in the following strict JSON format:

// {
// “type”: “session_type_here”,
// “title”: “Clear title in ${summaryLanguage}”,
// “summaryText”: “A fluent narrative-style summary in ${summaryLanguage}”,
// “sections”: [
// {
// “title”: “Section title 1”,
// “bullets”: [
// “- Point 1\n  - Sub-point 1.1\n  - Sub-point 1.2”,
// “- Point 2”
// ]
// }
// ],
// “icon”: “🎤”,
// “speakers”: {
// “speaker_0”: “speaker_0”,
// “speaker_1”: “Alice”
// },
// “calendarEvents”: [
// {
// “id”: “calendar-event-1”,
// “title”: “Marketing Sync”,
// “description”: “Weekly sync with marketing team”,
// “datetime”: “2025-07-11T15:00:00+07:00”,
// “participants”: [“Marketing Team”],
// “rawText”: “We have a marketing sync this afternoon at 3”
// }
// ]
// }

// Guidelines:
// 	•	Return only valid JSON output — no explanation, no extra formatting.
// 	•	Do not include any markdown syntax, no triple backticks.
// 	•	All bullet points must be factual and grounded in the text.
// 	•	Do not fabricate content. If a detail is unclear or missing, leave it blank or omit that section.
// 	•	Section titles must reflect the actual content (not generic).
// 	•	Respect the speaker_id structure; only map names if verifiable from the transcript.

// Transcript:
// ${transcript}

// ${description ? `\n\nAdditional context: ${description}` : ""}`;

//   console.log("🧠 [summarizeText] Sending prompt to OpenAI...");
//   const response = await client.chat.completions.create({
//     model: "gpt-4o-mini",
//     messages: [{ role: "user", content: prompt }],
//     temperature
//   });

//   let output = response.choices[0].message.content.trim();

//   // 🧹 Strip markdown block if present
//   if (output.startsWith("```json") || output.startsWith("```")) {
//     console.warn("⚠️ [summarizeText] Detected markdown block, stripping...");
//     output = output.replace(/```json|```/g, "").trim();
//   }

//   console.log("📦 [summarizeText] Raw OpenAI output:\n", output);

//   return output; // still JSON string
// };

// // ✅ Generate short questions from summary
// exports.generateShortQuestions = async (transcription, languageCode = "en") => {
//   const prompt = `
// You are a helpful assistant. Based on the transcription below, generate 5 short, relevant, and clear questions someone might ask to better understand or recall the content. Return only a JSON object with this format:

// {
//   "short_questions": ["...", "...", "..."]
// }

// Use ${languageCode} for the questions.

// Transcription:
// ${transcription}
//   `;

//   const response = await client.chat.completions.create({
//     model: "gpt-4o-mini",
//     messages: [{ role: "user", content: prompt }],
//     temperature: 0.4
//   });

//   const output = response.choices[0].message.content.trim();

//   // Try parsing and fallback
//   try {
//     return JSON.parse(output);
//   } catch (err) {
//     return { short_questions: [] };
//   }
// };

// // ✅ Answer user question from summary
// exports.answerQuestionFromSummary = async (transcription, question) => {
//   console.log("🔍 Starting: answerQuestionFromSummary");

//   // Log input values
//   console.log("📝 Received transcription:", transcription.slice(0, 500) + (transcription.length > 500 ? "..." : ""));
//   console.log("❓ User question:", question);

//   const prompt = `
// You are a helpful assistant. Use the transcription below to directly answer the user's question. 
// Do not add any introduction like "Based on the transcript" or "According to the audio." Just give the answer plainly and concisely. 
// If the answer is not clearly present, reply with only: "I'm not sure based on the transcription."

// Transcript:
// ${transcription}

// User Question:
// ${question}
//   `;

//   try {
//     console.log("📤 Sending request to OpenAI...");

//     const response = await client.chat.completions.create({
//       model: "gpt-4o-mini",
//       messages: [{ role: "user", content: prompt }],
//       temperature: 0.5
//     });

//     const answer = response.choices[0].message.content.trim();

//     // Log response
//     console.log("✅ Received response from OpenAI:", answer);

//     return answer;
//   } catch (error) {
//     console.error("❌ Error while generating answer:", error);
//     throw error;
//   }
// };

// /**
//  * Generate flashcards from a given transcript
//  * @param {string} transcript - Full raw transcript text
//  * @param {string} languageCode - e.g., "en", "vi", etc.
//  * @returns {Promise<{flashcards: Array<{question: string, answer: string}>}>}
//  */
// exports.generateFlashcards = async (transcript, languageCode = "en") => {
//   const prompt = `
// You are a helpful assistant. Your task is to extract flashcards from the transcript below.

// Each flashcard should have:
// - A clear and concise question
// - A direct and informative answer

// Return a JSON object like this:
// {
//   "flashcards": [
//     { "question": "What is ...?", "answer": "..." },
//     { "question": "...", "answer": "..." }
//   ]
// }

// Guidelines:
// - Do NOT include any markdown syntax like \`\`\`
// - Return only raw JSON (no explanation)
// - Output must be strictly valid JSON only


// Use ${languageCode} for the content. Create 5–10 flashcards that cover the most important ideas or facts.

// Transcript:
// ${transcript}
//   `;

//   try {
//     console.log("📤 [generateFlashcards] Sending prompt to OpenAI...");
//     const response = await client.chat.completions.create({
//       model: "gpt-4o-mini",
//       messages: [{ role: "user", content: prompt }],
//       temperature: 0.5
//     });

//     let output = response.choices[0].message.content.trim();

//     // Strip markdown code block if needed
//     if (output.startsWith("```json") || output.startsWith("```")) {
//       console.warn("⚠️ [generateFlashcards] Detected markdown block, stripping...");
//       output = output.replace(/```json|```/g, "").trim();
//     }

//     console.log("📦 [generateFlashcards] Raw OpenAI output:\n", output);

//     // Try to parse JSON
//     const data = JSON.parse(output);
//     return data;
//   } catch (error) {
//     console.error("❌ [generateFlashcards] Error:", error);
//     return { flashcards: [] };
//   }
// };

// /**
//  * Generate quiz questions from a given transcript
//  * @param {string} transcript - Full raw transcript text
//  * @param {string} languageCode - e.g., "en", "vi", etc.
//  * @returns {Promise<{quiz: Array<{question: string, options?: string[], answer: string}>}>}
//  */
// exports.generateQuiz = async (transcript, languageCode = "en") => {
//   const prompt = `
// You are a helpful assistant. Based on the transcript below, generate 5 to 10 quiz questions to test understanding.

// Each question should follow one of these formats:
// - Multiple choice (provide 3–4 options and one correct answer)
// - True/False
// - Short answer (if relevant)

// Return only a valid JSON object with this format:
// {
//   "quiz": [
//     {
//       "question": "What is ...?",
//       "options": ["A", "B", "C", "D"],  // optional (for multiple choice)
//       "answer": "Correct answer here"
//     },
//     {
//       "question": "True or False: ...",
//       "answer": "True"
//     }
//   ]
// }

// Guidelines:
// - Do NOT include any markdown syntax like \`\`\`
// - Return only raw JSON (no explanation)
// - Output must be strictly valid JSON only

// Use ${languageCode} for all content.

// Transcript:
// ${transcript}
//   `;

//   try {
//     console.log("📤 [generateQuiz] Sending prompt to OpenAI...");
//     const response = await client.chat.completions.create({
//       model: "gpt-4o-mini",
//       messages: [{ role: "user", content: prompt }],
//       temperature: 0.5
//     });

//     let output = response.choices[0].message.content.trim();

//     // Strip markdown code block if needed
//     if (output.startsWith("```json") || output.startsWith("```")) {
//       console.warn("⚠️ [generateQuiz] Detected markdown block, stripping...");
//       output = output.replace(/```json|```/g, "").trim();
//     }

//     console.log("📦 [generateQuiz] Raw OpenAI output:\n", output);

//     // Try to parse JSON
//     const data = JSON.parse(output);
//     return data;
//   } catch (error) {
//     console.error("❌ [generateQuiz] Error:", error);
//     return { quiz: [] };
//   }
// };

// /**
//  * Generate a hierarchical mind-map from a transcript
//  * @param {string} transcript – Full raw transcript text
//  * @param {string} languageCode – e.g. "en", "vi", etc.
//  * @returns {Promise<{ mindmap: { title: string, children: Array } }>}
//  *
//  * Expected JSON schema:
//  * {
//  *   "mindmap": {
//  *     "title": "Root topic",
//  *     "children": [
//  *       {
//  *         "title": "Sub-topic 1",
//  *         "children": [
//  *           { "title": "Point 1.1" },
//  *           { "title": "Point 1.2" }
//  *         ]
//  *       },
//  *       {
//  *         "title": "Sub-topic 2",
//  *         "children": []
//  *       }
//  *     ]
//  *   }
//  * }
//  */
// exports.generateMindMap = async (transcript, languageCode = "en") => {
//   const prompt = `
// You are a helpful assistant. Read the transcript below and produce a concise,
// hierarchical mind-map that captures the main topics and sub-topics.

// Return ONLY a valid JSON object with this exact structure:

// {
//   "mindmap": {
//     "id": "root",    
//     "title": "Root topic in ${languageCode}",
//      "icon": "🎯",
//     "children": [
//       { "id": "n1", "title": "Sub-topic 1", "children": [ { "id": "n1a", "title": "Point 1.1", "children": [] } ] },
//       { "id": "n2","title": "Sub-topic 2", "children": [] }
//     ]
//   }
// }

// Guidelines:
// - Every node, including leaves, MUST include a "children" array. Use [] for leaves.
// - Every node MUST include a unique string "id" (use short IDs like "n1", "n2a", etc.).
// - Keep the hierarchy between 2 to 4 levels where appropriate (e.g., root → topic → sub-topic → detail).
// - Include an appropriate emoji in the "icon" field to represent the session's subject or tone (e.g., 🎯, 🎤, 💼, 📚, 🧠, 🚀).
// - Use ${languageCode} for all text values.
// - Do NOT include any markdown syntax like \`\`\`
// - Do NOT add any explanation or comments.
// - Output must be strictly valid JSON only.

// Transcript:
// ${transcript}
//   `;

//   try {
//     console.log("📤 [generateMindmap] Sending prompt to OpenAI…");
//     const response = await client.chat.completions.create({
//       model: "gpt-4o-mini",
//       messages: [{ role: "user", content: prompt }],
//       temperature: 0.4
//     });

//     let output = response.choices[0].message.content.trim();

//     // Strip accidental markdown fences
//     if (output.startsWith("```json") || output.startsWith("```")) {
//       console.warn("⚠️ [generateMindmap] Detected markdown block, stripping…");
//       output = output.replace(/```json|```/g, "").trim();
//     }

//     console.log("📦 [generateMindmap] Raw OpenAI output:\n", output);

//     const data = JSON.parse(output);
//     return data;
//   } catch (error) {
//     console.error("❌ [generateMindmap] Error:", error);
//     return { mindmap: { title: "Untitled", children: [] } };
//   }
// };
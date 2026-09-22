// functions/utils/llm/gemini.js
require("dotenv").config();

const { GoogleGenerativeAI } = require("@google/generative-ai");
const BaseProvider = require("./base");

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY || "");

/**
 * Gemini adapter implementing BaseProvider.generate()
 */
class GeminiProvider extends BaseProvider {
  /**
   * @param {object} params
   * @param {string|Array} params.prompt - plain string OR [{ text: "…" }]
   * @param {number} [params.temperature=0.6]
   * @param {string} [params.model] - optional override model
   * @returns {Promise<string>}
   */
  async generate({ prompt, temperature = 0.6, model }) {
    const modelName = model || process.env.GEMINI_MODEL || "gemini-1.5-pro";
    const genModel  = genAI.getGenerativeModel({ model: modelName });

    const input =
      typeof prompt === "string"
        ? prompt
        : Array.isArray(prompt)
          ? prompt
          : String(prompt);

    try {
      console.log(`🔹 [GeminiProvider] Calling ${modelName} (temp=${temperature})`);
      const res = await genModel.generateContent(input, { temperature });
      const text = res.response.text().trim();
      console.log(`✅ [GeminiProvider] Received ${text.length} chars`);
      return text;
    } catch (err) {
      console.error("❌ [GeminiProvider] API call failed", {
        status: err.status,
        message: err.message,
      });
      throw err;
    }
  }
}

module.exports = GeminiProvider;
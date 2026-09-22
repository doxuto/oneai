// functions/utils/llm/grok.js
require("dotenv").config();

const OpenAI       = require("openai");
const BaseProvider = require("./base");

// Initialise Grok client once per cold-start
const groq = new OpenAI({
  apiKey: process.env.GROK_API_KEY || "",
});

/**
 * Grok provider implementing BaseProvider.generate()
 */
class GrokProvider extends BaseProvider {
  /**
   * Generate completion with Grok
   * @param {object} params
   * @param {string|Array} params.prompt
   * @param {number} [params.temperature=0.6]
   * @param {string} [params.model] - optional model override
   * @returns {Promise<string>}
   */
  async generate({ prompt, temperature = 0.6, model }) {
    const modelName = model || process.env.GROK_MODEL || "grok-1.0";

    const messages =
      typeof prompt === "string"
        ? [{ role: "user", content: prompt }]
        : prompt;

    try {
      console.log(`🔹 [GrokProvider] Calling ${modelName} (temp=${temperature})`);
      const res = await groq.chat.completions.create({
        model: modelName,
        messages,
        temperature,
      });

      const text = res.choices[0].message.content.trim();
      console.log(`✅ [GrokProvider] Received ${text.length} chars`);

      return text;
    } catch (err) {
      console.error("❌ [GrokProvider] API call failed:", {
        status: err.status,
        message: err.message,
      });
      throw err;
    }
  }
}

module.exports = GrokProvider; // CommonJS export
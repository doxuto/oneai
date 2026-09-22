// functions/utils/llm/openai.js
require("dotenv").config();

const OpenAI       = require("openai");
const BaseProvider = require("./base");

const client = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY || "",
});

class OpenAIProvider extends BaseProvider {
  /**
   * Generate completion from OpenAI
   * @param {object} params
   * @param {string|Array} params.prompt
   * @param {number} [params.temperature=0.6]
   * @param {string} [params.model] - override model (optional)
   * @returns {Promise<string>}
   */
  async generate({ prompt, temperature = 0.6, model }) {
    const messages =
      typeof prompt === "string"
        ? [{ role: "user", content: prompt }]
        : prompt;

    const modelId = model || process.env.OPENAI_MODEL || "gpt-4o-mini";

    const res = await client.chat.completions.create({
      model: modelId,
      messages,
      temperature,
    });

    return res.choices[0].message.content.trim();
  }
}

module.exports = OpenAIProvider;
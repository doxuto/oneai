const OpenAIProvider = require("./openai");
const GeminiProvider = require("./gemini");
const GrokProvider   = require("./grok");

/**
 * Dynamically selects and instantiates an LLM provider.
 * @param {string} [providerId] - Optional explicit provider id ("openai", "gemini", "grok")
 *                                 Falls back to process.env.LLM_VENDOR or "openai"
 * @returns {object} Provider instance
 */
function getProvider(providerId) {
  const vendor = (providerId || process.env.LLM_VENDOR || "openai").toLowerCase();
  switch (vendor) {
    case "gemini":
      return new GeminiProvider();
    case "grok":
      return new GrokProvider();
    case "openai":
      return new OpenAIProvider();
    default:
      throw new Error(`Unsupported LLM provider: ${vendor}`);
  }
}

module.exports = { getProvider };
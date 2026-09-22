/**
 * Base class for LLM providers.
 * Defines common interface.
 */
class BaseProvider {
  /**
   * Generate completion from the LLM provider.
   *
   * @param {object} params
   * @param {string|Array|object} params.prompt – prompt text or structured messages
   * @param {number} [params.temperature=0.6] – generation temperature
   * @param {string} [params.model] – (optional) override default model ID
   * @returns {Promise<string>} generated text
   */
  /* eslint-disable no-unused-vars */
  async generate({ prompt, temperature = 0.6, model }) {
    throw new Error("generate() not implemented");
  }
}

module.exports = BaseProvider;
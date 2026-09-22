// utils/getAudioDuration.js
const mm = require('music-metadata');

/**
 * Get duration in seconds from audio buffer
 * @param {Buffer} buffer
 * @returns {Promise<number>} duration in seconds
 */
async function getAudioDurationFromBuffer(buffer) {
  try {
    const metadata = await mm.parseBuffer(buffer);
    return metadata.format.duration || 0;
  } catch (err) {
    console.error("❌ Failed to read duration from audio buffer:", err.message);
    return 0;
  }
}

module.exports = { getAudioDurationFromBuffer };
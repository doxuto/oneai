const tagService = require('../../../services/tag.service');

/**
 * ✅ Controller: Update a tag's name
 */
module.exports = async (req, res) => {
  try {
    const result = await tagService.updateTag(req, res);
    return result; // tagService handles response formatting
  } catch (error) {
    console.error("🔥 [updateTag] Unexpected error:", error);
    return res.status(500).json({ success: false, message: "Internal server error" });
  }
};
const minutesService = require('../../../services/minutes.service');
const { successResponse, errorResponse, notFoundResponse } = require('../../../utils/responseHelper');

module.exports = async (req, res) => {
  try {
    const userId = req.user?.user_id;
    const { id: minuteId } = req.params;
    const { title, iconAsset, tags, summaryText, transcription } = req.body;

    const updated = await minutesService.updateMinute(userId, minuteId, {
      title,
      iconAsset,
      tags,
      summaryText,
      transcription
    });

    if (updated === null) {
      return notFoundResponse(res, "Minute not found");
    }

    if (Object.keys(updated).length === 0) {
      return res.status(400).json(errorResponse("No valid fields provided to update"));
    }

    return successResponse(res, updated, "Minute updated successfully");
  } catch (error) {
    console.error("🔥 [updateMinute] Error:", error);
    return res.status(500).json(errorResponse(error.message || "Internal Server Error"));
  }
};
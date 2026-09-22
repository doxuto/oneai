const minutesService = require('../../../services/minutes.service');
const { successResponse, notFoundResponse, errorResponse } = require("../../../utils/responseHelper");

module.exports = async (req, res) => {
    const userId = req.user?.user_id;
    const minuteId = req.params.id;

    console.log(`📥 [DELETE Minute] Request received. userId=${userId}, minuteId=${minuteId}`);

    if (!userId || !minuteId) {
        console.warn(`⚠️ [DELETE Minute] Missing userId or minuteId.`);
        return successResponse(res, {}, "Missing userId or minuteId.", 400);
    }

    try {
        const result = await minutesService.deleteMinute(userId, minuteId);

        if (result) {
            console.log(`✅ [DELETE Minute] Minute deleted successfully for userId=${userId}, minuteId=${minuteId}`);
            return successResponse(res, {}, "Minute deleted successfully.");
        } else {
            console.warn(`⚠️ [DELETE Minute] Minute not found. userId=${userId}, minuteId=${minuteId}`);
            return notFoundResponse(res, "Minute not found.");
        }

    } catch (error) {
        console.error(`❌ [DELETE Minute] Error deleting minute: ${error.message}`);
        return res.status(500).json(errorResponse("Internal Server Error"));
    }
};
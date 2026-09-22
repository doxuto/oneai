const minutesService = require('../../../services/minutes.service');
const { successResponse, notFoundResponse, errorResponse } = require("../../../utils/responseHelper");

module.exports = async (req, res) => {
    const userId = req.user?.user_id;
    const minuteId = req.params.id;

    console.log(`📥 [GET Minute] Request received. userId=${userId}, minuteId=${minuteId}`);

    if (!userId || !minuteId) {
        console.warn(`⚠️ [GET Minute] Missing userId or minuteId. userId=${userId}, minuteId=${minuteId}`);
        return res.status(400).json(errorResponse("Missing userId or minuteId"));
    }

    try {
        const minute = await minutesService.getMinuteById(userId, minuteId);

        if (minute) {
            console.log(`✅ [GET Minute] Found minute: ${minuteId} for user: ${userId}`);
            return successResponse(res, minute, "Minute fetched successfully");
        } else {
            console.warn(`⚠️ [GET Minute] Minute not found: ${minuteId} for user: ${userId}`);
            return notFoundResponse(res, "Minute not found");
        }

    } catch (error) {
        console.error(`❌ [GET Minute] Error retrieving minute: ${error.message}`);
        return res.status(500).json(errorResponse("Internal Server Error"));
    }
};
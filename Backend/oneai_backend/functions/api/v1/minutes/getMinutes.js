const _ = require('lodash');
const minutesService = require('../../../services/minutes.service');
const { successResponse, errorResponse } = require("../../../utils/responseHelper");

module.exports = async (req, res) => {
    const userEmail = req.user?.email;
    const limit = parseInt(req.query.limit) >= 1 ? parseInt(req.query.limit) : 10;
    const sort = req.query.sort || 'createdAt:desc';
    const tags = req.query.tags || '';
    const search = req.query.search || '';
    const startDate = req.query.startDate || '';
    const endDate = req.query.endDate || '';
    const startAfterDocId = req.query.startAfterDocId || null;

    console.log(`📥 [GET Minutes] Request received:
    - userEmail=${userEmail}
    - limit=${limit}
    - sort=${sort}
    - tags=${tags}
    - search=${search}
    - startDate=${startDate}
    - endDate=${endDate}
    - startAfterDocId=${startAfterDocId}`);

    if (!userEmail) {
        console.warn(`⚠️ [GET Minutes] Missing user email.`);
        return res.status(400).json(errorResponse("Missing user email."));
    }

    try {
        const result = await minutesService.getMinutes({
            userId: req.user.user_id,
            limit,
            email: userEmail,
            sort,
            tags,
            search,
            startDate,
            endDate,
            startAfterDocId
        });

        console.log(`✅ [GET Minutes] Found ${result.data.length} minutes for user: ${userEmail}`);

        return successResponse(res, {
            total: result.data.length,
            data: result.data,
            nextPageCursor: result.nextPageCursor || null
        }, "Minutes fetched successfully");

    } catch (error) {
        console.error(`❌ [GET Minutes] Error retrieving minutes: ${error.message}`);
        return res.status(500).json(errorResponse("Internal Server Error"));
    }
};
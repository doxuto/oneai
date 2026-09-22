const { db } = require('../../../config/config-firebase');
const { successResponse, notFoundResponse, errorResponse } = require("../../../utils/responseHelper");

/**
 * GET /api/v1/transcription/:taskId/status
 * 
 * ✅ API to check status of a speech transcription job
 * ✅ Only allows access for the owner of the job (userId check)
 * ✅ Returns standardized response with status, progress, step, and GCS output uri
 */
module.exports = async (req, res) => {
    const userId = req.user?.user_id;
    const taskId = req.params.taskId;

    console.log(`📥 [GET Transcription Status] Request received. userId=${userId}, taskId=${taskId}`);

    // ✅ Validate required params
    if (!userId || !taskId) {
        console.warn(`⚠️ [GET Transcription Status] Missing userId or taskId.`);
        return res.status(400).json(errorResponse("Missing userId or taskId"));
    }

    try {
        // ✅ Get document from Firestore
        const docRef = db.collection('speechJobs').doc(taskId);
        const docSnap = await docRef.get();

        if (!docSnap.exists) {
            // ✅ Return not found if job doesn't exist
            console.warn(`⚠️ [GET Transcription Status] Task not found: ${taskId}`);
            return notFoundResponse(res, "Transcription task not found");
        }

        const data = docSnap.data();

        // ✅ Check user ownership
        if (data.userId !== userId) {
            console.warn(`🚫 [GET Transcription Status] User mismatch. userId=${userId}, job.userId=${data.userId}`);
            return res.status(403).json(errorResponse("You are not authorized to view this transcription task"));
        }

        // ✅ Map job status to API response
        let status = data.status || "IN_PROGRESS";

        // ✅ Build response object
        const response = {
            status,
            operationId: data.operationId ?? null,                                       
            lastCheckedAt: data.lastCheckedAt ?? null,    // last checked timestamp (optional)
            minuteId: data.minuteId ?? null,              // related minuteId (optional)
            resultsGcsUri: data.resultsGcsUri ?? null     // transcription file URI (optional)
        };

        console.log(`✅ [GET Transcription Status] Success: ${JSON.stringify(response)}`);
        return successResponse(res, response, "Transcription status fetched");

    } catch (error) {
        // ✅ Handle unexpected server error
        console.error(`❌ [GET Transcription Status] Error: ${error.message}`);
        return res.status(500).json(errorResponse("Internal Server Error"));
    }
};
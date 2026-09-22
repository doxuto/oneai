const { db, bucket } = require('../../../config/config-firebase');
const { successResponse, notFoundResponse, errorResponse } = require("../../../utils/responseHelper");

module.exports = async (req, res) => {
  const userId = req.user?.user_id;
  const minuteId = req.params.id;

  console.log(`📥 [GET Transcript] Incoming request. userId=${userId}, minuteId=${minuteId}`);

  if (!userId || !minuteId) {
    console.warn(`⚠️ Missing userId or minuteId. userId=${userId}, minuteId=${minuteId}`);
    return res.status(400).json(errorResponse("Missing userId or minuteId"));
  }

  try {
    const docRef = db.collection('users').doc(userId).collection('minutes').doc(minuteId);
    const docSnap = await docRef.get();

    if (!docSnap.exists) {
      console.warn(`⚠️ Minute document not found. userId=${userId}, minuteId=${minuteId}`);
      return notFoundResponse(res, "Minute not found");
    }

    // ✅ Extract transcription directly from Firestore metadata
    const transcription = docSnap.get('metadata.transcription');

    if (!transcription) {
      console.warn("⚠️ metadata.transcription is missing in document.");
      return notFoundResponse(res, "Transcript not available for this minute");
    }

    console.log("✅ Transcript successfully loaded from metadata.");
    return successResponse(res, { transcription }, "Transcript fetched successfully");

  } catch (error) {
    console.error("❌ Error fetching transcript from Firestore:", error.message);
    return res.status(500).json(errorResponse("Internal Server Error"));
  }
};
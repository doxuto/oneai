const { mapSpeakers } = require("../../../services/ai.service");
const {
  successResponse,
  errorResponse,
} = require("../../../utils/responseHelper");
const { db, FieldValue } = require("../../../config/config-firebase");

/**
 * POST /api/v1/minutes/:id/map-speakers
 *
 * Workflow:
 * 1. If metadata/speakers exists → return it.
 * 2. Else load transcription (or summaryText) from metadata.
 * 3. Send text to LLM → get speaker mapping.
 * 4. Store speaker mapping under metadata/speakers and return it.
 */
module.exports = async (req, res) => {
  const userId   = req.user?.user_id;
  const minuteId = req.params.id;

  if (!userId || !minuteId) {
    return res
      .status(400)
      .json(errorResponse("Missing userId or minuteId"));
  }

  try {
    const minuteRef  = db.collection("users").doc(userId)
                         .collection("minutes").doc(minuteId);
    const speakersRef = minuteRef.collection("metadata").doc("speakers");

    /* ── 1. Return cached speakers if present ───────────────────────── */
    const cachedSnap = await speakersRef.get();
    if (cachedSnap.exists) {
      return successResponse(
        res,
        { speakers: cachedSnap.data() },
        "Speakers already mapped."
      );
    }

    /* ── 2. Load transcription (or summaryText) from metadata ───────── */
    let transcriptText = "";

    const transSnap = await minuteRef.collection("metadata").doc("transcription").get();
    if (transSnap.exists && transSnap.data()?.transcript) {
      transcriptText = transSnap.data().transcript.trim();
    }

    if (!transcriptText) {
      return errorResponse(res, "Transcript or summary content is missing.");
    }

    /* ── 3. Generate speaker mapping with AI ────────────────────────── */
    const speakers = await mapSpeakers(transcriptText);

    /* ── 4. Persist speakers & respond ──────────────────────────────── */
    await speakersRef.set({
      ...speakers,
      generatedAt: FieldValue.serverTimestamp(),
    });

    return successResponse(
      res,
      { speakers },
      "Speakers mapped and stored successfully."
    );

  } catch (err) {
    console.error("🔥 [mapSpeakers API] Error:", err.message);
    return errorResponse(res, err.message || "Failed to map speakers");
  }
};
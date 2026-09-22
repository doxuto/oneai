/**
 *  GET /api/v1/minutes/:id/speakers
 *
 *  Tự động tạo speaker map nếu chưa tồn tại.
 */

const { db, FieldValue } = require("../../../config/config-firebase");
const {
  successResponse,
  errorResponse,
  notFoundResponse
} = require("../../../utils/responseHelper");
const { mapSpeakers } = require("../../../services/ai.service");

module.exports = async (req, res) => {
  try {
    const userId   = req.user?.user_id;
    const minuteId = req.params.id;

    if (!userId || !minuteId) {
      return res
        .status(400)
        .json(errorResponse("Missing userId or minuteId"));
    }

    /* ── Firestore refs ───────────────────────────────────────────── */
    const minuteRef   = db.collection("users").doc(userId)
                          .collection("minutes").doc(minuteId);
    const speakersRef = minuteRef.collection("metadata").doc("speakers");

    /* ── 1. Trả cache nếu có ──────────────────────────────────────── */
    const snap = await speakersRef.get();
    if (snap.exists) {
      return successResponse(
        res,
        { speakers: snap.data() },
        "Speakers fetched successfully"
      );
    }

    /* ── 2. Nạp transcript (hoặc summary) ─────────────────────────── */
    let textForPrompt = "";

    const transSnap = await minuteRef.collection("metadata").doc("transcription").get();
    if (transSnap.exists && transSnap.data()?.transcript) {
      textForPrompt = transSnap.data().transcript.trim();
    }

    if (!textForPrompt) {
      const sumSnap = await minuteRef.collection("metadata").doc("summary").get();
      if (sumSnap.exists && sumSnap.data()?.summaryText) {
        textForPrompt = sumSnap.data().summaryText.trim();
      }
    }

    if (!textForPrompt) {
      return notFoundResponse(res, "No transcription or summary available to map speakers.");
    }

    /* ── 3. Gọi AI mapSpeakers ────────────────────────────────────── */
    const speakersMap = await mapSpeakers(textForPrompt);

    /* ── 4. Lưu vào Firestore ─────────────────────────────────────── */
    await speakersRef.set({
      ...speakersMap
    });

    /* ── 5. Trả về client ─────────────────────────────────────────── */
    return successResponse(
      res,
      { speakers: speakersMap },
      "Speakers mapped and stored successfully"
    );

  } catch (err) {
    console.error("🔥 [getSpeakers] Error:", err);
    return res
      .status(500)
      .json(errorResponse(err.message || "Internal Server Error"));
  }
};
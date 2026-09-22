const { db, bucket } = require("../../../config/config-firebase");
const { answerQuestionFromSummary } = require("../../../services/ai.service");
const {
  successResponse,
  notFoundResponse,
  errorResponse
} = require("../../../utils/responseHelper");

// ✅ POST /api/v1/minutes/:id/chat (với transcriptionUri)
module.exports = async (req, res) => {
  const userId = req.user?.user_id;
  const minuteId = req.params.id;
  const { question, languageCode = "en-US" } = req.body;

  console.log(`💬 [POST Chat] Incoming request`);
  console.log(`🔍 userId: ${userId}`);
  console.log(`🆔 minuteId: ${minuteId}`);
  console.log(`❓ question: ${question}`);
  console.log(`🌐 languageCode: ${languageCode}`);

  if (!userId || !minuteId || !question) {
    console.warn(`⚠️ [POST Chat] Missing required parameters`);
    return res.status(400).json(errorResponse("Missing userId, minuteId, or question"));
  }

  try {

    console.log(`📄 [POST Chat] Fetching minute document from Firestore`);
    const minuteRef = db.collection("users")
      .doc(userId)
      .collection("minutes")
      .doc(minuteId);

    /* ── 2. Load transcript or summary from metadata ─────────────── */
    let textForPrompt = "";

    const transSnap = await minuteRef
      .collection("metadata")
      .doc("transcription")
      .get();

    if (transSnap.exists) {
      const t = transSnap.data();
      if (Array.isArray(t.sections) && t.sections.length) {
        textForPrompt = t.sections
          .map((s) => s.title || s.text || "")
          .join("\n")
          .trim();
      }
    }

    if (!textForPrompt) {
      const sumSnap = await minuteRef
        .collection("metadata")
        .doc("summary")
        .get();
      if (sumSnap.exists && sumSnap.data()?.summaryText) {
        textForPrompt = sumSnap.data().summaryText.trim();
      }
    }

    if (!textForPrompt) {
      return errorResponse(res, "Transcript content is missing.");
    }

    console.log(`💡 [POST Chat] Sending transcription to OpenAI for question answering...`);
    const answer = await answerQuestionFromSummary(textForPrompt, question, languageCode);
    console.log(`✅ [POST Chat] Answer received from OpenAI: ${answer}`);

    return successResponse(res, {
      question,
      answer,
      minuteId
    }, "Chat response generated successfully");

  } catch (error) {
    console.error(`🔥 [POST Chat] Firestore error occurred:`, error.message);
    return res.status(500).json(errorResponse("Internal server error"));
  }
};
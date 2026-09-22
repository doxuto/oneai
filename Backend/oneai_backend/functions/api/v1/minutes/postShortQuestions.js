const { generateShortQuestions } = require("../../../services/ai.service");
const { successResponse, notFoundResponse, errorResponse } = require("../../../utils/responseHelper");
const { db, bucket } = require("../../../config/config-firebase");

/**
 * POST /api/v1/minutes/:id/questions
 * 
 * Generate 5 short questions based on the summaryText of a minute.
 * - If shortQuestions already exist in metadata/shortQuestions, return them.
 * - If not, generate via OpenAI and store into metadata.
 */
module.exports = async (req, res) => {
  const userId   = req.user?.user_id;
  const minuteId = req.params.id;
  const languageCode = req.body.languageCode || "en";

  if (!userId || !minuteId) {
    return res.status(400).json(errorResponse("Missing userId or minuteId"));
  }

  try {
    const minuteRef = db.collection("users").doc(userId).collection("minutes").doc(minuteId);

    /* 1️⃣  Return existing short questions if present */
    const shortQRef = minuteRef.collection("metadata").doc("shortQuestions");
    const shortQSnap = await shortQRef.get();
    if (shortQSnap.exists) {
      const existing = shortQSnap.data()?.short_questions || [];
      return successResponse(
        res,
        { short_questions: existing },
        existing.length ? "Short questions already exist" : "No questions stored"
      );
    }

    /* 2️⃣  Load transcript (or summary) from metadata collection */
    let textForPrompt = "";

    const transSnap = await minuteRef.collection("metadata").doc("transcription").get();
    if (transSnap.exists) {
      const t = transSnap.data();
      if (Array.isArray(t.sections)) {
        textForPrompt = t.sections.map(s => s.title || s.text || "").join("\n").trim();
      }
    }

    if (!textForPrompt) {
      const sumSnap = await minuteRef.collection("metadata").doc("summary").get();
      if (sumSnap.exists && sumSnap.data()?.summaryText) {
        textForPrompt = sumSnap.data().summaryText;
      }
    }

    if (!textForPrompt) {
      return errorResponse(res, "Transcript content is missing");
    }

    /* 3️⃣  Call OpenAI to generate questions */
    const result = await generateShortQuestions(textForPrompt, languageCode);
    if (!Array.isArray(result.short_questions) || !result.short_questions.length) {
      throw new Error("OpenAI did not return any questions");
    }

    /* 4️⃣  Store questions back to metadata collection */
    await shortQRef.set({
      short_questions: result.short_questions,
      generatedAt: new Date().toISOString(),
    });

    return successResponse(res, result, "Generated and stored short questions successfully");

  } catch (err) {
    console.error("🔥 [postShortQuestions] Error:", err.message);
    return errorResponse(res, err.message || "Failed to generate short questions");
  }
};
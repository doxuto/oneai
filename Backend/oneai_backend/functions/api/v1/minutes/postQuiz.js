const { generateQuiz } = require("../../../services/ai.service");
const {
  successResponse,
  notFoundResponse,
  errorResponse,
} = require("../../../utils/responseHelper");
const { db } = require("../../../config/config-firebase");

/**
 * POST /api/v1/minutes/:id/quiz
 *
 * Workflow:
 * 1. If metadata/quiz already exists → return it.
 * 2. Else load transcript (or summary) from metadata/{transcription|summary}.
 * 3. Send text to OpenAI → get quiz.
 * 4. Store quiz under metadata/quiz and return it.
 */
module.exports = async (req, res) => {
  const userId = req.user?.user_id;
  const minuteId = req.params.id;
  const languageCode = req.body.languageCode || "en";

  if (!userId || !minuteId) {
    return res
      .status(400)
      .json(errorResponse("Missing userId or minuteId"));
  }

  try {
    const minuteRef = db
      .collection("users")
      .doc(userId)
      .collection("minutes")
      .doc(minuteId);

    const quizRef = minuteRef.collection("metadata").doc("quiz");

    /* ── 1. Return cached quiz, if any ───────────────────────────── */
    const quizSnap = await quizRef.get();
    if (quizSnap.exists) {
      const quizData = quizSnap.data()?.quiz || [];
      return successResponse(
        res,
        { quiz: quizData },
        quizData.length ? "Quiz already exists." : "No quiz stored."
      );
    }

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

    /* ── 3. Generate quiz with OpenAI ────────────────────────────── */
    const result = await generateQuiz(textForPrompt, languageCode);

    if (!Array.isArray(result.quiz) || !result.quiz.length) {
      throw new Error("OpenAI did not return a valid quiz array.");
    }

    /* ── 4. Persist quiz in metadata & respond ───────────────────── */
    await quizRef.set({
      quiz: result.quiz,
      generatedAt: new Date().toISOString(),
    });

    return successResponse(
      res,
      result,
      "Quiz generated and stored successfully."
    );
  } catch (err) {
    console.error("🔥 [generateQuiz] Error:", err.message);
    return errorResponse(res, err.message || "Failed to generate quiz");
  }
};
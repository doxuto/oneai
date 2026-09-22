const { generateFlashcards } = require("../../../services/ai.service");
const {
  successResponse,
  notFoundResponse,
  errorResponse,
} = require("../../../utils/responseHelper");
const { db } = require("../../../config/config-firebase");

/**
 * POST /api/v1/minutes/:id/flashcards
 *
 * Workflow:
 * 1. If metadata/flashcards exists → return it.
 * 2. Else load transcription (or summary) from metadata.
 * 3. Send text to OpenAI → get flashcards.
 * 4. Store flashcards under metadata/flashcards and return them.
 */
module.exports = async (req, res) => {
  const userId   = req.user?.user_id;
  const minuteId = req.params.id;
  const languageCode = req.body.languageCode || "en";

  if (!userId || !minuteId) {
    return res
      .status(400)
      .json(errorResponse("Missing userId or minuteId"));
  }

  try {
    /* ────────── Firestore refs ────────── */
    const minuteRef     = db.collection("users")
                            .doc(userId)
                            .collection("minutes")
                            .doc(minuteId);
    const flashcardsRef = minuteRef.collection("metadata").doc("flashcards");

    /* 1️⃣  Return cached flashcards if present */
    const cacheSnap = await flashcardsRef.get();
    if (cacheSnap.exists) {
      const flashcards = cacheSnap.data()?.flashcards || [];
      return successResponse(
        res,
        { flashcards },
        flashcards.length ? "Flashcards already exist." : "No flashcards stored."
      );
    }

    /* 2️⃣  Load transcript (or summary) text */
    let textForPrompt = "";

    const transSnap = await minuteRef
      .collection("metadata")
      .doc("transcription")
      .get();

    if (transSnap.exists) {
      const data = transSnap.data();
      if (Array.isArray(data.sections) && data.sections.length) {
        textForPrompt = data.sections
          .map((s) => s.title || s.text || "")
          .filter(Boolean)
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

    /* 3️⃣  Generate flashcards with OpenAI */
    const openaiResult = await generateFlashcards(textForPrompt, languageCode);

    if (
      !openaiResult ||
      !Array.isArray(openaiResult.flashcards) ||
      !openaiResult.flashcards.length
    ) {
      throw new Error("OpenAI did not return a valid flashcards array.");
    }

    /* 4️⃣  Persist flashcards and respond */
    await flashcardsRef.set(
      {
        flashcards: openaiResult.flashcards,
        generatedAt: new Date().toISOString(),
      },
      { merge: true }
    );

    return successResponse(
      res,
      openaiResult,
      "Flashcards generated and stored successfully."
    );
  } catch (err) {
    console.error("🔥 [generateFlashcards] Error:", err.message);
    return errorResponse(res, err.message || "Failed to generate flashcards");
  }
};
const { generateMindMap } = require("../../../services/ai.service");
const {
  successResponse,
  notFoundResponse,
  errorResponse,
} = require("../../../utils/responseHelper");
const { db } = require("../../../config/config-firebase");

/**
 * POST /api/v1/minutes/:id/mindmap
 *
 * 1. If metadata/mindmap exists → return it.
 * 2. Else read transcript (or summary) from metadata collection.
 * 3. Call OpenAI to generate mind-map; store result under metadata/mindmap.
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
    const minuteRef  = db.collection("users").doc(userId)
                         .collection("minutes").doc(minuteId);
    const mindmapRef = minuteRef.collection("metadata").doc("mindmap");

    /* ── 1. Return cached mind-map if present ───────────────────── */
    const cacheSnap = await mindmapRef.get();
    if (cacheSnap.exists) {
      return successResponse(res, cacheSnap.data(), "Mind map already exists.");
    }

    /* ── 2. Load transcript (or summary) from metadata ──────────── */
    let textForPrompt = "";

    const transSnap = await minuteRef.collection("metadata").doc("transcription").get();
    if (transSnap.exists) {
      const t = transSnap.data();
      if (Array.isArray(t.sections) && t.sections.length) {
        textForPrompt = t.sections
          .map(s => s.title || s.text || "")
          .join("\n")
          .trim();
      }
    }

    if (!textForPrompt) {
      const sumSnap = await minuteRef.collection("metadata").doc("summary").get();
      if (sumSnap.exists && sumSnap.data()?.summaryText) {
        textForPrompt = sumSnap.data().summaryText.trim();
      }
    }

    if (!textForPrompt) {
      return errorResponse(res, "Transcript content is missing.");
    }

    /* ── 3. Generate mind-map with OpenAI ───────────────────────── */
    const result = await generateMindMap(textForPrompt, languageCode);

    /* ── 4. Persist mind-map & respond ─────────────────────────── */
    await mindmapRef.set({
      ...result,
      generatedAt: new Date().toISOString(),
    });

    return successResponse(
      res,
      result,
      "Mind map generated and stored successfully."
    );

  } catch (err) {
    console.error("🔥 [postMindmap] Error:", err.message);
    return errorResponse(res, err.message || "Failed to generate mind map");
  }
};
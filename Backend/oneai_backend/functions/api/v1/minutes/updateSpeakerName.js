/**
 *  updateSpeakerName.js
 *  ---------------------------------------------------------------------------
 *  PATCH  /api/v1/minutes/:minuteId/speakers/:speakerId
 *
 *  Body JSON:
 *    {
 *      "newName": "John Doe"
 *    }
 *
 *  If the speakers document or the specific speakerId does not exist,
 *  the handler will create / add it instead of returning 404.
 * ---------------------------------------------------------------------------*/

const { db, FieldValue } = require("../../../config/config-firebase");
const {
  successResponse,
  errorResponse
} = require("../../../utils/responseHelper");

module.exports = async (req, res) => {
  try {
    /* ────────── 1. Auth / Params / Body ──────────────────────────────── */
    const userId                    = req.user?.user_id;
    const { id: minuteId, speakerId } = req.params;
    const { newName }               = req.body ?? {};

    if (!userId || !minuteId || !speakerId || !newName?.trim()) {
      return res
        .status(400)
        .json(errorResponse("Missing userId, minuteId, speakerId or newName"));
    }

    /* ────────── 2. Firestore reference ──────────────────────────────── */
    const speakersDocRef = db
      .collection("users").doc(userId)
      .collection("minutes").doc(minuteId)
      .collection("metadata").doc("speakers");

    /* ────────── 3. Upsert speaker name ──────────────────────────────── */
    //  - If the document doesn’t exist, set() will create it.
    //  - If it exists, merge keeps other fields intact.
    await speakersDocRef.set(
      {
        [speakerId]: newName.trim()
      },
      { merge: true }
    );

    console.log(
      "✅ [updateSpeakerName] minute=%s %s → %s",
      minuteId,
      speakerId,
      newName
    );

    /* ────────── 4. Return updated map ───────────────────────────────── */
    const updated = (await speakersDocRef.get()).data();
    return successResponse(
      res,
      updated,
      `Speaker ${speakerId} set to "${newName.trim()}"`
    );
  } catch (err) {
    console.error("🔥 [updateSpeakerName] Error:", err);
    return res
      .status(500)
      .json(errorResponse(err.message || "Internal Server Error"));
  }
};
/**
 *  GET /api/v1/minutes/:id/calendar-events
 *
 *  Trả về:
 *    {
 *      "success": true,
 *      "data": {
 *        "calendarEvents": [ { id, title, description, datetime, participants, rawText }, ... ]
 *      }
 *    }
 */

const { db } = require("../../../config/config-firebase");
const {
  successResponse,
  errorResponse,
  notFoundResponse
} = require("../../../utils/responseHelper");

module.exports = async (req, res) => {
  try {
    const userId  = req.user?.user_id;
    const { id: minuteId } = req.params;

    if (!userId || !minuteId) {
      return res
        .status(400)
        .json(errorResponse("Missing userId or minuteId"));
    }

    const docRef = db
      .collection("users").doc(userId)
      .collection("minutes").doc(minuteId)
      .collection("metadata").doc("calendarEvents");

    const snap = await docRef.get();

    if (!snap.exists) {
      return notFoundResponse(res, "Calendar events not found");
    }

    const data = snap.data() || {};
    const events = data.calendarEvents ?? [];

    return successResponse(
      res,
      { calendarEvents: events },
      "Calendar events fetched successfully"
    );
  } catch (err) {
    console.error("🔥 [getCalendarEvents] Error:", err);
    return res
      .status(500)
      .json(errorResponse(err.message || "Internal Server Error"));
  }
};
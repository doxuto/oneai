/**
 *  PATCH /api/v1/minutes/:minuteId/calendar-events/:eventId
 *  ---------------------------------------------------------------------------
 *  Body JSON – chỉ gửi các field cần sửa, ví dụ:
 *    {
 *      "title": "New title",
 *      "datetime": "2025-07-15T09:00:00+07:00"
 *    }
 *
 *  Cập-nhật đúng phần tử có id === :eventId trong mảng calendarEvents.
 * ---------------------------------------------------------------------------*/

const { db, FieldValue } = require("../../../config/config-firebase");
const {
  successResponse,
  errorResponse
} = require("../../../utils/responseHelper");

module.exports = async (req, res) => {
  try {
    /* ────────── 1. Params / Body / Auth ───────────────────────────── */
    const userId = req.user?.user_id;
    const { id: minuteId, eventId } = req.params;
    const updates = req.body ?? {};

    if (!userId || !minuteId || !eventId || Object.keys(updates).length === 0) {
      return res
        .status(400)
        .json(errorResponse("Missing userId, minuteId, eventId or update fields"));
    }

    /* ────────── 2. Firestore ref ──────────────────────────────────── */
    const docRef = db
      .collection("users").doc(userId)
      .collection("minutes").doc(minuteId)
      .collection("metadata").doc("calendarEvents");

    /* ────────── 3. Load current events array ──────────────────────── */
    const snap = await docRef.get();
    const events = snap.exists ? snap.data().calendarEvents ?? [] : [];

    /* ────────── 4. Find & update event by id ──────────────────────── */
    const index = events.findIndex(ev => ev.id === eventId);
    if (index === -1) {
      return res.status(404).json(errorResponse("Event not found"));
    }

    events[index] = { ...events[index], ...updates };

    /* ────────── 5. Save back & respond ────────────────────────────── */
    await docRef.set(
      {
        calendarEvents: events,
        updatedAt: FieldValue.serverTimestamp()
      },
      { merge: true }
    );

    return successResponse(
      res,
      { calendarEvents: events },
      `Event ${eventId} updated`
    );
  } catch (err) {
    console.error("🔥 [patchCalendarEvent] Error:", err);
    return res
      .status(500)
      .json(errorResponse(err.message || "Internal Server Error"));
  }
};
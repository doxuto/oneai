const express = require("express");
const router = express.Router();
const { authMiddleware } = require("../../../middlewares/auth");

// ──────────────── Minute core routes ────────────────
router.get("/", authMiddleware, require("./getMinutes"));
router.get("/:id", authMiddleware, require("./getMinuteById"));
router.patch("/:id", authMiddleware, require("./updateMinute"));
router.delete("/:id", authMiddleware, require("./deleteMinute"));

// ──────────────── Transcription & Metadata ────────────────
router.get("/:id/transcription", authMiddleware, require("./getTranscriptByMinuteId"));
router.post("/:id/flashcards", authMiddleware, require("./postFlashcards"));
router.post("/:id/quiz", authMiddleware, require("./postQuiz"));
router.post("/:id/questions", authMiddleware, require("./postShortQuestions"));
router.post("/:id/mindmap", authMiddleware, require("./postMindMap"));

// ──────────────── Chat Interaction ────────────────
router.post("/:id/chat", authMiddleware, require("./chat"));

// ──────────────── Speaker Management ────────────────
router.get("/:id/speakers", authMiddleware, require("./getSpeakers"));
router.post("/:id/speakers", authMiddleware, require("./mapSpeakers"));
router.patch("/:id/speakers/:speakerId", authMiddleware, require("./updateSpeakerName"));

// ──────────────── Calendar Events ────────────────
router.get("/:id/calendar-events", authMiddleware, require("./getCalendarEvents"));
router.patch("/:id/calendar-events/:eventId", authMiddleware, require("./updateCalendarEvents"));

module.exports = router;
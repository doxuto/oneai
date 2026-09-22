const express = require("express");
const router = express.Router();

const minutesRoutes = require("./minutes");
const transcriptionRoutes = require("./transcription");
const tagsRoutes = require("./tags");
const youtubeRoutes = require("./youtube");
const userRoutes = require("./user");
const summaryRoutes = require("./summary");

router.use("/minutes", minutesRoutes);
router.use("/transcription", transcriptionRoutes);
router.use("/tags", tagsRoutes);
router.use("/user", userRoutes);
router.use("/youtube", youtubeRoutes);
router.use("/summary", summaryRoutes);

module.exports = router;

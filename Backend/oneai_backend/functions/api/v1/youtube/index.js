const express = require("express");
const router = express.Router();
const { authMiddleware } = require("../../../middlewares/auth");

router.post("/mp3", authMiddleware, require("./youtubeToMp3"));

module.exports = router;

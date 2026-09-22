const express = require("express");
const router = express.Router();
const { authMiddleware } = require("../../../middlewares/auth");

router.post("/transcribe", authMiddleware, require("./transcribe"));
router.post("/youtube", authMiddleware, require("./transcribeYoutube"));
router.post("/file", authMiddleware, require("./transcribeFile"));
router.get("/:taskId/status", authMiddleware, require("./getStatus"));
router.get("/:taskId/result", authMiddleware, require("./getResult"));

module.exports = router;

const express = require("express");
const router = express.Router();
const { authMiddleware } = require("../../../middlewares/auth");
router.get("/me", authMiddleware, require("./getMe"));
router.post("/reward", authMiddleware, require("./postReward"));

module.exports = router;

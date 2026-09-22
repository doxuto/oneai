const express = require("express");
const router = express.Router();
const { authMiddleware } = require("../../../middlewares/auth");

router.post("/pdf", authMiddleware, require("./pdf"));


module.exports = router;
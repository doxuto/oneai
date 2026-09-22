const express = require("express");
const router = express.Router();
const { authMiddleware } = require("../../../middlewares/auth");

router.get("/", authMiddleware, require("./getTags"));
router.put("/:id", authMiddleware, require("./updateTag"));
router.post("/", authMiddleware, require("./createTag"));
router.delete("/:id", authMiddleware, require("./deleteTag"));

module.exports = router;

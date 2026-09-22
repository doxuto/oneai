const express = require("express");
const router = express.Router();
const { db } = require("../../../config/config-firebase");
const { successResponse, notFoundResponse, errorResponse, unauthorizedResponse } = require("../../../utils/responseHelper");

router.get("/me", async (req, res) => {
  try {
    const userId = req.user?.uid;
    if (!userId) {
      console.warn("⚠️ Unauthorized access attempt to /me");
      return unauthorizedResponse(res, "Unauthorized");
    }

    const userDoc = await db.collection("users").doc(userId).get();
    if (!userDoc.exists) {
      console.warn(`⚠️ User not found: ${userId}`);
      return notFoundResponse(res, "User not found");
    }

    const userData = userDoc.data();
    console.log(`✅ Fetched user data for ${userId}`);

    return successResponse(res, { user: userData }, "Fetched user info");
  } catch (error) {
    console.error("🔥 Error fetching user:", error);
    return res.status(500).json(errorResponse("Internal server error"));
  }
});

module.exports = router;
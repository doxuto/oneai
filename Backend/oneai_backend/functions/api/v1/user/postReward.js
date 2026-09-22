const express = require("express");
const router = express.Router();
const { db } = require("../../../config/config-firebase");
const {
  successResponse,
  notFoundResponse,
  errorResponse,
  unauthorizedResponse,
  badRequestResponse,
} = require("../../../utils/responseHelper");

module.exports = async (req, res) => {
  try {
    // 🔐 Check if user is authenticated
    const userId = req.user?.uid;
    if (!userId) {
      console.warn("⚠️ Unauthorized access attempt to reward endpoint");
      return unauthorizedResponse(res, "Unauthorized");
    }

    // 📨 Extract rewardAmount from request body
    const { rewardAmount } = req.body;
    console.log(`📥 Received rewardAmount:`, rewardAmount);

    // ✅ Validate rewardAmount: must be a positive number within a sane range
    if (
      typeof rewardAmount !== "number" ||
      isNaN(rewardAmount) ||
      rewardAmount <= 0 ||
      rewardAmount > 1_000_000
    ) {
      console.warn(`⚠️ Invalid rewardAmount from user ${userId}:`, rewardAmount);
      return badRequestResponse(res, "Invalid reward amount");
    }

    const userRef = db.collection("users").doc(userId);

    // 🔎 Fetch user document from Firestore
    const userDoc = await userRef.get();
    if (!userDoc.exists) {
      console.warn(`❌ User document not found for UID: ${userId}`);
      return notFoundResponse(res, "User not found");
    }

    const userData = userDoc.data();
    const currentCredit = userData.credit || 0;

    // ➕ Calculate new credit amount
    const newCredit = currentCredit + rewardAmount;

    // 💾 Update the user's credit field in Firestore
    await userRef.update({ credit: newCredit });
    console.log(`✅ Successfully updated credit for user ${userId}`);
    console.log(`🔁 Credit before: ${currentCredit}, after: ${newCredit}`);

    // 📤 Send success response with updated credit
    return successResponse(res, { credit: newCredit }, "Reward applied successfully");
  } catch (error) {
    // 🔥 Handle unexpected errors
    console.error("🔥 Error while applying reward to user:", error);
    return res.status(500).json(errorResponse("Internal server error"));
  }
};
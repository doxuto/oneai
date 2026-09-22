const express = require("express");
const router = express.Router();
const { db } = require("../config/config-firebase");

const SECRET = process.env.REVENUECAT_WEBHOOK_SECRET;

const premiumEvents = [
  "INITIAL_PURCHASE",
  "RENEWAL",
  "UNCANCELLATION",
  "SUBSCRIPTION_EXTENDED"
];

const downgradeEvents = [
  "CANCELLATION",
  "EXPIRATION",
  "REFUND"
];

const isStillPremium = (expirationAtMs) => {
  if (!expirationAtMs) return false;
  return expirationAtMs > Date.now();
};

router.post("/revenuecat-webhook", async (req, res) => {
  try {
    const authHeader = req.headers["authorization"];
    if (authHeader !== `Bearer ${SECRET}`) {
      console.warn("❌ Webhook rejected: Invalid Authorization header");
      return res.status(403).json({ error: "Invalid webhook secret" });
    }

    const payload = req.body;
    const eventData = payload.event;

    console.log("📩 Incoming RevenueCat webhook event:");
    console.log(JSON.stringify(eventData, null, 2));

    const { type: eventType, app_user_id: userId, expiration_at_ms: expirationAtMs } = eventData;

    if (!userId) {
      console.warn("⚠️ Webhook missing app_user_id");
      return res.status(400).json({ error: "Missing app_user_id" });
    }

    const userRef = db.collection("users").doc(userId);

    if (premiumEvents.includes(eventType)) {
      await userRef.update({ plan: "premium" });
      console.log(`✅ User ${userId} set to PREMIUM via event: ${eventType}`);
    } else if (downgradeEvents.includes(eventType)) {
      if (isStillPremium(expirationAtMs)) {
        await userRef.update({ plan: "premium" });
        console.log(`✅ User ${userId} remains PREMIUM until ${new Date(expirationAtMs).toISOString()} (event: ${eventType})`);
      } else {
        await userRef.update({ plan: "free" });
        console.log(`✅ User ${userId} downgraded to FREE via event: ${eventType}`);
      }
    } else {
      console.log(`ℹ️ Event ${eventType} received — no plan update`);
    }

    return res.status(200).json({ success: true, message: "Webhook handled successfully" });

  } catch (err) {
    console.error("🔥 Error processing RevenueCat webhook:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

module.exports = router;

const { onRequest } = require("firebase-functions/v2/https");
const { checkPendingSpeechJobs } = require("../services/speech.service");

exports.scheduledCheckJobs = onRequest(async (req, res) => {
    console.log("⏰ [scheduledCheckJobs] Triggered by Cloud Scheduler (HTTP)");
    try {
        const clientName = req.query.client || "default"; // 👉 Multi client support
        console.log(`👉 Client param: ${clientName}`);
        await checkPendingSpeechJobs();
        res.status(200).send(`✅ Speech jobs check completed`);
    } catch (err) {
        console.error("❌ Error in scheduledCheckJobs:", err);
        res.status(500).send("❌ Failed to check speech jobs.");
    }
});
const { onSchedule } = require("firebase-functions/v2/scheduler");
const resetDailyCredit = require("./tasks/resetDailyFreeCredit");

exports.runDailyJobs = onSchedule(
  {
    schedule: "0 0 * * *",
    timeZone: "UTC",
    timeoutSeconds: 300,
    memory: "256MiB",
  },
  async (event) => {
    try {
      await resetDailyCredit();
    } catch (error) {
      console.error("❌ Daily job error:", error);
    }
  }
);
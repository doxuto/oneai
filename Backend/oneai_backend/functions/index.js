// ✅ Firebase Functions V2 + Express Setup
const express = require("express");
const cors = require("cors");
const { onRequest } = require("firebase-functions/v2/https");

// ✅ Import middlewares + routes + triggers
const { authMiddleware } = require("./middlewares/auth");
const apiRouter = require("./api");
const revenuecatWebhook = require("./webhooks/revenuecatWebhook");
const {
  createUserProfile,
  updateLastLogin,
  deleteUserData
} = require('./triggers/user');

const { runDailyJobs } = require("./scheduled/runDailyJobs");

// ✅ Initialize Express App
const app = express();

// =======================
// ✅ Global Middlewares
// =======================

// ✅ Enable CORS for all routes
app.use(cors({ origin: true }));

// ✅ Only apply body parsers for non multipart
app.use(express.json()); // JSON payload
app.use(express.raw({ limit: "130mb", type: "application/x-www-form-urlencoded" }));
app.use(express.raw({ limit: "150mb", type: "multipart/related" }));

// =======================
// ✅ Public Webhook (no auth)
// =======================
app.use("/webhooks", revenuecatWebhook); // 👈 MUST come before authMiddleware

// =======================
// ✅ Authenticated API
// =======================
app.use("/", authMiddleware, apiRouter);

// =======================
// ✅ Firebase Exports
// =======================
exports.api = onRequest({ timeoutSeconds: 240, memory: "512MiB" }, app);
exports.createUserProfile = createUserProfile;
exports.updateLastLogin = updateLastLogin;
exports.deleteUserData = deleteUserData;
exports.runDailyJobs = runDailyJobs;
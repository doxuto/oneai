import { onRequest } from "firebase-functions/v2/https";
import { liveDeps } from "../lib/deps.js";
import { handleSsv } from "./reward.js";
import { keyStore } from "./verify.js";

const keys = keyStore();

/**
 * PUBLIC on purpose: Google has no Firebase credentials. The ECDSA signature
 * is the authentication. Never log the query string.
 * Region follows setGlobalOptions (asia-southeast1) so the grant transaction
 * is co-located with Firestore; register the deployed URL in the AdMob console.
 */
export const adRewardSsv = onRequest(
  { memory: "256MiB", timeoutSeconds: 30, maxInstances: 10, cors: false },
  async (req, res) => {
    const raw = req.originalUrl.includes("?") ? req.originalUrl.slice(req.originalUrl.indexOf("?") + 1) : "";
    const out = await handleSsv(raw, liveDeps(), keys);
    res.status(out.status).send(out.body);
  },
);

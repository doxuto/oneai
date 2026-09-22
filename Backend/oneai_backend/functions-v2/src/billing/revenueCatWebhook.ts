import { onRequest } from "firebase-functions/v2/https";
import { liveDeps } from "../lib/deps.js";
import { log } from "../lib/logging.js";
import { REVENUECAT_WEBHOOK_SECRET } from "../lib/params.js";
import { authorized, handleRevenueCat } from "./revenuecat.js";

/** Third-party caller ⇒ onRequest is the documented exception to onCall. */
export const revenueCatWebhook = onRequest(
  { memory: "256MiB", timeoutSeconds: 30, maxInstances: 10, secrets: [REVENUECAT_WEBHOOK_SECRET], cors: false },
  async (req, res) => {
    if (req.method !== "POST") { res.status(405).send("method not allowed"); return; }
    if (!authorized(req.header("authorization"), REVENUECAT_WEBHOOK_SECRET.value())) {
      log.warn("revenuecat.unauthorized", { ip: req.ip ?? null });
      res.status(401).send("unauthorized");
      return;
    }
    const out = await handleRevenueCat(req.body, liveDeps());
    res.status(out.status).send(out.body);
  },
);

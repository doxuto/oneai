import { onSchedule } from "firebase-functions/v2/scheduler";
import { liveDeps } from "../lib/deps.js";
import { APP_TIMEZONE } from "../lib/time.js";
import { sweep } from "./sweep.js";

/** 03:00 Vietnam, daily. Scheduled functions do not fire in the emulator; the handler is tested directly. */
export const sweepOrphanFiles = onSchedule(
  { schedule: "0 3 * * *", timeZone: APP_TIMEZONE, memory: "512MiB", timeoutSeconds: 540, retryCount: 1 },
  async () => { await sweep(liveDeps()); },
);

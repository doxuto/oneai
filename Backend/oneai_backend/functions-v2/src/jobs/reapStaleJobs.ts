import { onSchedule } from "firebase-functions/v2/scheduler";
import { liveDeps } from "../lib/deps.js";
import { reapStaleJobs as reap } from "./reap.js";

/** Every 15 minutes. Scheduled functions do not fire in the emulator; the handler is tested directly. */
export const reapStaleJobs = onSchedule(
  { schedule: "every 15 minutes", memory: "256MiB", timeoutSeconds: 300, retryCount: 1 },
  async () => { await reap(liveDeps()); },
);

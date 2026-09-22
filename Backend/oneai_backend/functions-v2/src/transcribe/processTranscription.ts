import { onTaskDispatched } from "firebase-functions/v2/tasks";
import { liveDeps } from "../lib/deps.js";
import { log } from "../lib/logging.js";
import { ELEVENLABS_API_KEY, OPENAI_API_KEY } from "../lib/params.js";
import { runPipeline } from "./pipeline.js";
import { TaskPayload } from "./types.js";

const MAX_ATTEMPTS = 3;

/**
 * The heavy worker. Everything v1 did inside one HTTP request (512MiB / 240s)
 * now runs here with the memory and time it actually needs, and a client that
 * left the app still gets its note.
 */
export const processTranscription = onTaskDispatched(
  {
    memory: "2GiB",
    timeoutSeconds: 540,
    maxInstances: 10,
    secrets: [ELEVENLABS_API_KEY, OPENAI_API_KEY],
    retryConfig: { maxAttempts: MAX_ATTEMPTS, minBackoffSeconds: 30, maxBackoffSeconds: 300 },
    rateLimits: { maxConcurrentDispatches: 10 },
  },
  async (request) => {
    const parsed = TaskPayload.safeParse(request.data);
    if (!parsed.success) {
      // A malformed task will never succeed; log and drop rather than retry.
      log.error("pipeline.bad_payload", { issues: parsed.error.issues.length });
      return;
    }
    const attempt = request.retryCount ?? 0;
    await runPipeline(parsed.data, liveDeps(), { attempt, maxAttempts: MAX_ATTEMPTS });
  },
);

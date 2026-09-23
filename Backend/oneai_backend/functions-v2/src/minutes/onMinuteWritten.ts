/**
 * Keeps the denormalised counters honest:
 *   users/{uid}.minuteCount           = number of notes
 *   users/{uid}/tags/{tagId}.minuteCount = number of notes carrying that tag
 *
 * Triggers are at-least-once, so counters are RECOMPUTED with aggregation
 * queries rather than incremented — a redelivery writes the same value again.
 */
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { getDb } from "../lib/admin.js";
import { liveDeps } from "../lib/deps.js";
import { log } from "../lib/logging.js";
import { GEMINI_API_KEY, OPENAI_API_KEY } from "../lib/params.js";
import { embedMinute, needsEmbedding } from "../search/embedding.js";
import type { MinuteDoc } from "./_shared.js";
import { recountAfterMinuteWrite } from "./recount.js";

export const onMinuteWritten = onDocumentWritten(
  { document: "users/{uid}/minutes/{minuteId}", memory: "512MiB", timeoutSeconds: 120, secrets: [OPENAI_API_KEY, GEMINI_API_KEY] },
  async (event) => {
    const uid = event.params.uid;
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    const touched = await recountAfterMinuteWrite(getDb(), uid, before, after);
    log.info("minute.recounted", { uid, eventId: event.id, tags: touched.length });

    // S11-01/02: (re)embed a ready note whose title/summary changed. The write
    // of `embedding` itself re-triggers this function once more and stops here
    // because the hash then matches — no loop, one provider call per change.
    const deps = liveDeps();
    if (after && needsEmbedding(after as MinuteDoc, deps.services.embedder.dimension)) {
      const r = await embedMinute(deps, uid, event.params.minuteId);
      log.info("minute.embedded", { uid, minuteId: event.params.minuteId, result: r });
    }
  },
);

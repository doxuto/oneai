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
import { log } from "../lib/logging.js";
import { recountAfterMinuteWrite } from "./recount.js";

export const onMinuteWritten = onDocumentWritten(
  { document: "users/{uid}/minutes/{minuteId}", memory: "256MiB", timeoutSeconds: 60 },
  async (event) => {
    const uid = event.params.uid;
    const before = event.data?.before.data();
    const after = event.data?.after.data();
    const touched = await recountAfterMinuteWrite(getDb(), uid, before, after);
    log.info("minute.recounted", { uid, eventId: event.id, tags: touched.length });
  },
);

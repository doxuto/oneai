/**
 * S11-01/02 — nightly catch-up for notes that never got a vector: migrated v1
 * notes, notes whose embed call failed, and every note when EMBEDDING_DIM
 * changes (the hash includes the dimension, so all become stale at once).
 * Bounded per run; the rest waits for tomorrow.
 */
import { onSchedule } from "firebase-functions/v2/scheduler";
import type { Deps } from "../lib/deps.js";
import { liveDeps } from "../lib/deps.js";
import { log } from "../lib/logging.js";
import { GEMINI_API_KEY, OPENAI_API_KEY } from "../lib/params.js";
import type { MinuteDoc } from "../minutes/_shared.js";
import { embedMinute, needsEmbedding } from "../search/embedding.js";
import { APP_TIMEZONE } from "../lib/time.js";

export const BACKFILL_MAX_PER_RUN = 500;

export async function backfill(deps: Deps, max = BACKFILL_MAX_PER_RUN): Promise<{ scanned: number; stored: number; failed: number }> {
  const t0 = Date.now();
  let scanned = 0, stored = 0, failed = 0;
  const dimension = deps.services.embedder.dimension;
  // collectionGroup over every user's notes, ready ones only; the hash check
  // below skips the ones already embedded at this dimension.
  const snap = await deps.db.collectionGroup("minutes").where("status", "==", "ready").select("status", "title", "summary", "transcriptPreview", "embeddingHash").limit(5000).get();
  for (const d of snap.docs) {
    if (stored + failed >= max) break;
    scanned++;
    if (!needsEmbedding(d.data() as MinuteDoc, dimension)) continue;
    const uid = d.ref.parent.parent?.id;
    if (!uid) continue;
    const r = await embedMinute(deps, uid, d.id);
    if (r === "stored") stored++;
    else if (r === "failed") failed++;
  }
  log.info("search.backfill", { scanned, stored, failed, ms: Date.now() - t0 });
  return { scanned, stored, failed };
}

export const backfillEmbeddings = onSchedule(
  { schedule: "30 3 * * *", timeZone: APP_TIMEZONE, memory: "512MiB", timeoutSeconds: 540, retryCount: 0, secrets: [OPENAI_API_KEY, GEMINI_API_KEY] },
  async () => { await backfill(liveDeps()); },
);

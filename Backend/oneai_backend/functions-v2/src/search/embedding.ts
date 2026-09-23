/**
 * S11-01/02 — one embedding per ready note, stored on the minute doc as a
 * Firestore vector (`embedding`), plus `embeddingHash` so a redelivered trigger
 * or an unchanged summary never pays for a second call.
 */
import { createHash } from "node:crypto";
import { FieldValue, type Firestore } from "firebase-admin/firestore";
import type { Deps } from "../lib/deps.js";
import { log } from "../lib/logging.js";
import type { MinuteDoc } from "../minutes/_shared.js";

/** Title + summary + the transcript preview: what a user would remember a note by. */
export function embeddingText(m: Pick<MinuteDoc, "title" | "summary" | "transcriptPreview">): string {
  const parts: string[] = [];
  if (m.title) parts.push(m.title);
  const s = m.summary;
  if (s) {
    if (s.text) parts.push(s.text);
    for (const sec of s.sections ?? []) {
      parts.push(sec.title);
      for (const b of sec.bullets ?? []) parts.push(b);
    }
  }
  if (m.transcriptPreview) parts.push(m.transcriptPreview);
  return parts.join("\n").trim();
}

export const embeddingHash = (text: string, dimension: number) =>
  createHash("sha1").update(`${dimension}:${text}`).digest("hex");

/** True when the doc is ready and its vector is missing or stale. */
export function needsEmbedding(m: MinuteDoc & { embeddingHash?: string }, dimension: number): boolean {
  if (m.status !== "ready") return false;
  const text = embeddingText(m);
  if (!text) return false;
  return m.embeddingHash !== embeddingHash(text, dimension);
}

/**
 * Computes and stores the vector. Best effort: a provider outage is logged and
 * the note stays searchable by the client-side text search; the next write of
 * the doc (or the nightly backfill) retries.
 */
export async function embedMinute(deps: Deps, uid: string, minuteId: string): Promise<"stored" | "skipped" | "failed"> {
  const ref = deps.db.doc(`users/${uid}/minutes/${minuteId}`);
  const snap = await ref.get();
  if (!snap.exists) return "skipped";
  const m = snap.data() as MinuteDoc & { embeddingHash?: string };
  const dimension = deps.services.embedder.dimension;
  if (!needsEmbedding(m, dimension)) return "skipped";
  const text = embeddingText(m);
  try {
    const [vector] = await deps.services.embedder.embed([text], "document");
    if (!vector) return "failed";
    await ref.update({ embedding: FieldValue.vector(vector), embeddingHash: embeddingHash(text, dimension), embeddedAt: FieldValue.serverTimestamp() });
    return "stored";
  } catch (err) {
    log.warn("search.embed_failed", { uid, minuteId, err: err instanceof Error ? err.message : String(err) });
    return "failed";
  }
}

export interface Neighbour { minuteId: string; distance: number }

/** Nearest ready notes of one user. COSINE distance: 0 identical … 2 opposite. */
export async function nearestMinutes(db: Firestore, uid: string, queryVector: number[], limit: number, maxDistance: number): Promise<Neighbour[]> {
  const q = db.collection(`users/${uid}/minutes`)
    .where("status", "==", "ready")
    .findNearest({ vectorField: "embedding", queryVector: FieldValue.vector(queryVector), limit, distanceMeasure: "COSINE", distanceResultField: "vectorDistance", distanceThreshold: maxDistance });
  const snap = await q.get();
  return snap.docs.map((d) => ({ minuteId: d.id, distance: Number((d.data() as { vectorDistance?: number }).vectorDistance ?? 0) }));
}

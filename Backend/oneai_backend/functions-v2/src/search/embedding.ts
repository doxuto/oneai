/**
 * S11-01/02 — one embedding per ready note, stored on the minute doc as a
 * Firestore vector (`embedding`), plus `embeddingHash` so a redelivered trigger
 * or an unchanged summary never pays for a second call.
 */
import { createHash } from "node:crypto";
import { FieldValue, type Firestore } from "firebase-admin/firestore";
import type { Deps } from "../lib/deps.js";
import { log } from "../lib/logging.js";
import { toTranscript, type MinuteDoc } from "../minutes/_shared.js";
import { chunkDocId, chunkTranscript } from "./chunks.js";

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
    const chunkCount = await embedChunks(deps, uid, minuteId, m);
    await ref.update({ embedding: FieldValue.vector(vector), embeddingHash: embeddingHash(text, dimension), embeddedAt: FieldValue.serverTimestamp(), chunkCount });
    return "stored";
  } catch (err) {
    log.warn("search.embed_failed", { uid, minuteId, err: err instanceof Error ? err.message : String(err) });
    return "failed";
  }
}

/**
 * S11-01b: rewrites the note's transcript chunks (one vector each, one batch
 * call). Returns the number written; 0 when the note has no transcript. Old
 * chunks are removed first so a re-transcription never leaves stale ones.
 */
async function embedChunks(deps: Deps, uid: string, minuteId: string, m: MinuteDoc): Promise<number> {
  const col = deps.db.collection(`users/${uid}/minutes/${minuteId}/chunks`);
  const old = await col.select().get();
  if (!m.transcriptPath) {
    if (!old.empty) await Promise.all(old.docs.map((d) => d.ref.delete()));
    return 0;
  }
  const [buf] = await deps.bucket.file(m.transcriptPath).download();
  const transcript = toTranscript(JSON.parse(buf.toString("utf8")));
  const chunks = transcript ? chunkTranscript(transcript) : [];
  const vectors = chunks.length > 0 ? await deps.services.embedder.embed(chunks.map((c) => c.text), "document") : [];
  let batch = deps.db.batch();
  let n = 0;
  const commitIfFull = async () => { if (++n % 400 === 0) { await batch.commit(); batch = deps.db.batch(); } };
  for (const d of old.docs) { batch.delete(d.ref); await commitIfFull(); }
  chunks.forEach((c, i) => {
    batch.set(col.doc(chunkDocId(c.order)), { uid, minuteId, order: c.order, text: c.text, startSeconds: c.startSeconds, endSeconds: c.endSeconds, embedding: FieldValue.vector(vectors[i]!) });
  });
  await batch.commit();
  return chunks.length;
}

export interface Neighbour { minuteId: string; distance: number }
export interface ChunkHit { minuteId: string; order: number; text: string; startSeconds: number; endSeconds: number; distance: number }

/** Nearest transcript chunks across all of one user's notes (collection-group vector index). */
export async function nearestChunks(db: Firestore, uid: string, queryVector: number[], limit: number, maxDistance: number): Promise<ChunkHit[]> {
  const q = db.collectionGroup("chunks")
    .where("uid", "==", uid)
    .findNearest({ vectorField: "embedding", queryVector: FieldValue.vector(queryVector), limit, distanceMeasure: "COSINE", distanceResultField: "vectorDistance", distanceThreshold: maxDistance });
  const snap = await q.get();
  return snap.docs.map((d) => {
    const x = d.data() as { minuteId?: string; order?: number; text?: string; startSeconds?: number; endSeconds?: number; vectorDistance?: number };
    return { minuteId: x.minuteId ?? d.ref.parent.parent?.id ?? "", order: x.order ?? 0, text: x.text ?? "", startSeconds: x.startSeconds ?? 0, endSeconds: x.endSeconds ?? 0, distance: Number(x.vectorDistance ?? 0) };
  });
}

/** Nearest ready notes of one user. COSINE distance: 0 identical … 2 opposite. */
export async function nearestMinutes(db: Firestore, uid: string, queryVector: number[], limit: number, maxDistance: number): Promise<Neighbour[]> {
  const q = db.collection(`users/${uid}/minutes`)
    .where("status", "==", "ready")
    .findNearest({ vectorField: "embedding", queryVector: FieldValue.vector(queryVector), limit, distanceMeasure: "COSINE", distanceResultField: "vectorDistance", distanceThreshold: maxDistance });
  const snap = await q.get();
  return snap.docs.map((d) => ({ minuteId: d.id, distance: Number((d.data() as { vectorDistance?: number }).vectorDistance ?? 0) }));
}

/**
 * Source-file retention. The original audio/PDF is the only heavy object a
 * note owns (a transcript is a few KB); left alone it grows the bucket
 * forever. Each note gets `sourceExpiresAt` when it becomes ready, by plan;
 * a daily step deletes the bytes past that date and marks the note
 * `sourceState: "expired"` — the transcript, summary and every artifact stay,
 * only the player goes away. A bucket lifecycle rule (storage.lifecycle.json)
 * is the plan-independent backstop.
 */
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import type { Deps } from "../lib/deps.js";
import { log } from "../lib/logging.js";
import { minutePrefix } from "../minutes/_shared.js";
import { effectivePlan, type UserDoc } from "../users/_shared.js";

const DAY_MS = 24 * 60 * 60 * 1000;

/** null = keep indefinitely (retention -1). */
export function sourceExpiryFor(readyAt: Date, retentionDays: number): Date | null {
  if (retentionDays < 0) return null;
  return new Date(readyAt.getTime() + retentionDays * DAY_MS);
}

export interface RetentionReport {
  expired: number;
  extended: number;
}

/**
 * Deletes sources whose `sourceExpiresAt` has passed. Re-checks the owner's
 * CURRENT plan first: a user who upgraded after the note was made keeps their
 * audio for the longer window instead of losing it on the old schedule.
 */
export async function expireSources(deps: Deps, now = deps.now(), limit = 200): Promise<RetentionReport> {
  const report: RetentionReport = { expired: 0, extended: 0 };
  const snap = await deps.db.collectionGroup("minutes")
    .where("sourceState", "==", "available")
    .where("sourceExpiresAt", "<", Timestamp.fromDate(now))
    .limit(limit).get();

  const planCache = new Map<string, number>();
  for (const d of snap.docs) {
    const uid = d.ref.parent.parent?.id;
    if (!uid) continue;
    const data = d.data() as { statusUpdatedAt?: Timestamp; sourceExpiresAt?: Timestamp };

    let retention = planCache.get(uid);
    if (retention === undefined) {
      const user = (await deps.db.doc(`users/${uid}`).get()).data() as UserDoc | undefined;
      retention = deps.limits[effectivePlan(user ?? {}, now)].sourceRetentionDays;
      planCache.set(uid, retention);
    }
    const readyAt = data.statusUpdatedAt?.toDate() ?? data.sourceExpiresAt?.toDate() ?? now;
    const dueNow = sourceExpiryFor(readyAt, retention);
    if (dueNow === null || dueNow.getTime() > now.getTime()) {
      // Plan changed since the date was stamped — push it out, keep the bytes.
      await d.ref.update({ sourceExpiresAt: dueNow === null ? null : Timestamp.fromDate(dueNow) });
      report.extended++;
      continue;
    }

    await deps.bucket.deleteFiles({ prefix: `${minutePrefix(uid, d.id)}source/` });
    await d.ref.update({
      sourceState: "expired",
      sourcePath: null,
      sourceExpiredAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    report.expired++;
  }
  log.info("retention.done", { ...report });
  return report;
}

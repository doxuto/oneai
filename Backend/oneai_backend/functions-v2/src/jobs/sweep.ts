/**
 * Housekeeping v1 never had. Three kinds of leftovers:
 *   1. notes stuck in `uploading` — the client never finished (or never
 *      started) the upload; after 24 h delete the doc and any bytes.
 *   2. notes stuck in queued/transcribing/summarizing — the worker died or
 *      the task was lost; after 2 h fail the note and refund the credit.
 *   3. Storage prefixes with no note doc — e.g. a delete whose Storage step
 *      failed; remove the files.
 *   4. finished transcriptionJobs older than 7 days.
 *   5. source audio/PDF past the plan's retention window (retention.ts).
 * Pure over Deps so it runs against the emulator in tests.
 */
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import type { Deps } from "../lib/deps.js";
import { log } from "../lib/logging.js";
import { minutePrefix } from "../minutes/_shared.js";
import { failJob } from "../transcribe/pipeline.js";
import { expireSources } from "./retention.js";

export interface SweepReport {
  abandonedUploads: number;
  stuckJobs: number;
  orphanPrefixes: number;
  oldJobs: number;
  expiredSources: number;
}

const H = 60 * 60 * 1000;

export async function sweep(deps: Deps, now = deps.now()): Promise<SweepReport> {
  const report: SweepReport = { abandonedUploads: 0, stuckJobs: 0, orphanPrefixes: 0, oldJobs: 0, expiredSources: 0 };

  // 1. abandoned uploads (> 24 h)
  {
    const cutoff = Timestamp.fromDate(new Date(now.getTime() - 24 * H));
    const snap = await deps.db.collectionGroup("minutes")
      .where("status", "==", "uploading").where("createdAt", "<", cutoff).limit(200).get();
    for (const d of snap.docs) {
      const uid = d.ref.parent.parent?.id;
      if (!uid) continue;
      await deps.db.recursiveDelete(d.ref);
      await deps.bucket.deleteFiles({ prefix: minutePrefix(uid, d.id) }).catch(() => undefined);
      report.abandonedUploads++;
    }
  }

  // 2. stuck processing (> 2 h since the last status change). The 15-minute
  //    reaper catches these earlier when a job doc exists; this is the
  //    backstop for a note whose job doc is missing entirely.
  {
    const cutoff = Timestamp.fromDate(new Date(now.getTime() - 2 * H));
    const snap = await deps.db.collectionGroup("minutes")
      .where("status", "in", ["queued", "transcribing", "summarizing"])
      .where("statusUpdatedAt", "<", cutoff).limit(200).get();
    for (const d of snap.docs) {
      const uid = d.ref.parent.parent?.id;
      if (!uid) continue;
      const jobs = await deps.db.collection("transcriptionJobs").where("uid", "==", uid).where("minuteId", "==", d.id)
        .where("state", "in", ["queued", "running"]).limit(1).get();
      const job = jobs.docs[0];
      if (job) {
        await failJob(deps, { uid, minuteId: d.id, jobId: job.id }, { code: "stuck", message: "Processing did not finish. Please try again." });
      } else {
        await d.ref.update({
          status: "failed",
          failure: { code: "stuck", message: "Processing did not finish. Please try again." },
          statusUpdatedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(),
        });
      }
      report.stuckJobs++;
    }
  }

  // 3. orphan storage prefixes
  {
    const seen = new Set<string>();
    let pageToken: string | undefined;
    do {
      const [files, next] = await deps.bucket.getFiles({ prefix: "users/", autoPaginate: false, maxResults: 1000, pageToken });
      pageToken = (next as { pageToken?: string } | null)?.pageToken;
      for (const f of files) {
        const m = /^users\/([^/]+)\/minutes\/([^/]+)\//.exec(f.name);
        if (!m) continue;
        const key = `${m[1]}/${m[2]}`;
        if (seen.has(key)) continue;
        seen.add(key);
        const doc = await deps.db.doc(`users/${m[1]}/minutes/${m[2]}`).get();
        if (!doc.exists) {
          await deps.bucket.deleteFiles({ prefix: minutePrefix(m[1] ?? "", m[2] ?? "") });
          report.orphanPrefixes++;
        }
      }
    } while (pageToken);
  }

  // 4. old finished jobs (> 7 days)
  {
    const cutoff = Timestamp.fromDate(new Date(now.getTime() - 7 * 24 * H));
    const snap = await deps.db.collection("transcriptionJobs")
      .where("state", "in", ["done", "failed", "cancelled"]).where("finishedAt", "<", cutoff).limit(500).get();
    if (!snap.empty) {
      const batch = deps.db.batch();
      snap.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
      report.oldJobs = snap.size;
    }
  }

  // 5. source files past their retention (plan-based; see retention.ts)
  report.expiredSources = (await expireSources(deps, now)).expired;

  log.info("sweep.done", { ...report });
  return report;
}

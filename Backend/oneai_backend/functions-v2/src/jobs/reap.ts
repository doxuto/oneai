/**
 * Job-driven watchdog for the heavy worker. Cloud Tasks retries a crashed
 * attempt, but two things it cannot fix: a job whose last attempt died
 * mid-flight (`running` forever) and a task that was lost before the first
 * attempt (`queued` forever). Both leave the user staring at a spinner with a
 * credit spent. Every 15 minutes: fail them, refund, notify.
 *
 * Thresholds: a single attempt is capped at 540 s and there are at most 3
 * with ≤ 300 s backoff, so 30 minutes of `running` means nobody is coming.
 */
import { Timestamp } from "firebase-admin/firestore";
import type { Deps } from "../lib/deps.js";
import { log } from "../lib/logging.js";
import { failJob } from "../transcribe/pipeline.js";
import type { JobDoc } from "../transcribe/types.js";

export interface ReapOptions {
  runningMaxMs: number;
  queuedMaxMs: number;
  limit: number;
}

export const REAP_DEFAULTS: ReapOptions = {
  runningMaxMs: 30 * 60 * 1000,
  queuedMaxMs: 60 * 60 * 1000,
  limit: 100,
};

export interface ReapReport {
  running: number;
  queued: number;
  jobIds: string[];
}

export async function reapStaleJobs(deps: Deps, opts: Partial<ReapOptions> = {}): Promise<ReapReport> {
  const o = { ...REAP_DEFAULTS, ...opts };
  const now = deps.now().getTime();
  const report: ReapReport = { running: 0, queued: 0, jobIds: [] };
  const jobs = deps.db.collection("transcriptionJobs");

  const stale = [
    { state: "running" as const, field: "startedAt", cutoff: Timestamp.fromMillis(now - o.runningMaxMs), code: "stale", message: "Processing did not finish. Please try again." },
    { state: "queued" as const, field: "createdAt", cutoff: Timestamp.fromMillis(now - o.queuedMaxMs), code: "lost", message: "Processing never started. Please try again." },
  ];

  for (const s of stale) {
    const snap = await jobs.where("state", "==", s.state).where(s.field, "<", s.cutoff).limit(o.limit).get();
    for (const d of snap.docs) {
      const j = d.data() as JobDoc;
      await failJob(deps, { uid: j.uid, minuteId: j.minuteId, jobId: d.id }, { code: s.code, message: s.message });
      report[s.state]++;
      report.jobIds.push(d.id);
      log.warn("job.reaped", { jobId: d.id, uid: j.uid, minuteId: j.minuteId, state: s.state, attempt: j.attempt });
    }
  }

  log.info("reap.done", { running: report.running, queued: report.queued });
  return report;
}

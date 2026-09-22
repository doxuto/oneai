# Scheduled jobs

Targets firebase-functions 6.x, `firebase-functions/v2/scheduler` (backed by Cloud Scheduler + Pub/Sub). Cloud Scheduler API must be enabled; the CLI does it on first deploy.

## Syntax

```ts
import { onSchedule, type ScheduledEvent } from "firebase-functions/v2/scheduler";

// Form 1: schedule string only (defaults: region from setGlobalOptions or us-central1, timeZone UTC, retryCount 0)
export const heartbeat = onSchedule("every 5 minutes", async (event) => { /* … */ });

// Form 2: options object — use this one
export const nightlyCleanup = onSchedule(
  {
    schedule: "0 3 * * *",                 // unix-cron, or App Engine syntax: "every day 03:00", "every monday 09:00", "every 12 hours"
    timeZone: "Asia/Ho_Chi_Minh",          // IANA name; REQUIRED for anything that means "3 am for our users"
    region: "asia-southeast1",
    retryCount: 3,                          // Cloud Scheduler retries on non-2xx / timeout
    minBackoffSeconds: 60,
    maxBackoffSeconds: 600,
    maxRetrySeconds: 3600,
    maxDoublings: 3,
    timeoutSeconds: 540,                    // max for event functions
    memory: "512MiB",
    maxInstances: 1,                        // a scheduled job should never fan out into parallel copies of itself
  },
  async (event: ScheduledEvent) => {
    event.scheduleTime;                     // RFC3339 string — the time it was *supposed* to run; use as the idempotency key
    event.jobName;                          // Cloud Scheduler job name
  },
);
```

Schedule strings:

- unix-cron: `minute hour day-of-month month day-of-week` — `"0 3 * * *"` (03:00 daily), `"*/15 * * * *"` (every 15 min), `"0 9 * * 1"` (Mondays 09:00), `"0 0 1 * *"` (1st of month).
- App Engine: `"every 5 minutes"`, `"every day 03:00"`, `"every monday 09:00"`, `"1st,15th of month 00:00"`. Minimum interval is 1 minute either way.
- `timeZone` applies to both forms. Without it, `"every day 03:00"` is 03:00 UTC = 10:00 in Vietnam.

Each `onSchedule` creates one Cloud Scheduler job and one Pub/Sub topic. Renaming the function orphans the old job — delete via `firebase functions:delete` so the scheduler entry goes with it.

## Idempotency and overlap

- `retryCount > 0` means a run that throws is re-run; a run that succeeds after doing half the work is not. Both require the job to be resumable: claim `${name}:${event.scheduleTime}` in the ledger for "did this tick already complete", and store progress cursors for "where did it stop".
- Two ticks can overlap if a run exceeds the interval (a 10-minute job on `every 5 minutes`). `maxInstances: 1` prevents parallel *instances* but with `concurrency > 1` two events can still land on one instance. Set `concurrency: 1` on schedulers, or take a lease document in a transaction at the start (`_meta/leases/{jobName}` with `expiresAt`) and skip when held.
- The job is a Pub/Sub push; the platform's own at-least-once semantics apply. Same ledger.

```ts
async function acquireLease(name: string, ttlSeconds: number): Promise<boolean> {
  const ref = db.doc(`_meta/leases/${name}`);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Timestamp.now();
    if (snap.exists && snap.get("expiresAt").toMillis() > now.toMillis()) return false;
    tx.set(ref, { holder: process.env.K_REVISION ?? "local", acquiredAt: now, expiresAt: Timestamp.fromMillis(now.toMillis() + ttlSeconds * 1000) });
    return true;
  });
}
```

## Long jobs: paginate and chunk through a task queue

A scheduled function has at most 540 s. Do not loop over "all users" inline. Pattern: the scheduler **finds work and enqueues it**; task queue workers do it with retries and rate limits.

```ts
import { onSchedule } from "firebase-functions/v2/scheduler";
import { onTaskDispatched } from "firebase-functions/v2/tasks";
import { getFunctions } from "firebase-admin/functions";
import { getFirestore, Timestamp, FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions/logger";

const db = getFirestore();
const REGION = "asia-southeast1";
const PAGE = 500;

// 03:00 Vietnam time: purge soft-deleted notes older than 30 days.
export const purgeDeletedNotes = onSchedule(
  { schedule: "0 3 * * *", timeZone: "Asia/Ho_Chi_Minh", region: REGION, retryCount: 2, maxInstances: 1, concurrency: 1, timeoutSeconds: 540 },
  async (event) => {
    if (!(await acquireLease("purgeDeletedNotes", 600))) { logger.warn("purge already running"); return; }
    const cutoff = Timestamp.fromMillis(Date.now() - 30 * 86_400_000);
    const queue = getFunctions().taskQueue("purgeNotesChunk");
    let last: FirebaseFirestore.QueryDocumentSnapshot | undefined;
    let enqueued = 0;
    for (;;) {
      let q = db.collectionGroup("notes").where("isDeleted", "==", true).where("deletedAt", "<", cutoff)
        .orderBy("deletedAt").orderBy("__name__").select().limit(PAGE);       // ids only; composite CG index required
      if (last) q = q.startAfter(last);
      const page = await q.get();
      if (page.empty) break;
      await queue.enqueue({ paths: page.docs.map((d) => d.ref.path), scheduleTime: event.scheduleTime }, { dispatchDeadlineSeconds: 300 });
      enqueued += page.size;
      last = page.docs[page.docs.length - 1];
      if (page.size < PAGE) break;
    }
    logger.info("purge enqueued", { enqueued, cutoff: cutoff.toDate().toISOString() });
  },
);

export const purgeNotesChunk = onTaskDispatched(
  { region: REGION, retryConfig: { maxAttempts: 5, minBackoffSeconds: 30 }, rateLimits: { maxConcurrentDispatches: 4 }, timeoutSeconds: 300, maxInstances: 4 },
  async (req) => {
    const paths = (req.data as { paths: string[] }).paths;
    const bw = db.bulkWriter();
    for (const p of paths) bw.delete(db.doc(p));       // delete is idempotent; a retried chunk is harmless
    await bw.close();
  },
);
```

Why chunks of paths instead of re-querying in the worker: a worker that re-queries "the next 500" races with siblings; a fixed list of paths is deterministic and idempotent.

Other common jobs: reconcile denormalised counters with `count()` (`queries-and-indexes.md`), prune stale FCM tokens, delete anonymous users' data past 30 days, retry stuck `deleting` accounts, export daily backups (`maintenance.md`), refresh materialised leaderboard docs, expire subscriptions past `planExpiresAt` and update claims.

## Counter reconciliation (small, runs inline)

```ts
export const reconcileNoteCounts = onSchedule(
  { schedule: "every day 04:00", timeZone: "Asia/Ho_Chi_Minh", region: REGION, maxInstances: 1, concurrency: 1 },
  async () => {
    const users = await db.collection("users").select("noteCount").limit(1000).get();   // chunk with a cursor beyond 1000
    const bw = db.bulkWriter();
    for (const u of users.docs) {
      const agg = await db.collection(`users/${u.id}/notes`).where("isDeleted", "==", false).count().get();
      const real = agg.data().count;
      if ((u.get("noteCount") ?? 0) !== real) bw.update(u.ref, { noteCount: real, updatedAt: FieldValue.serverTimestamp() });
    }
    await bw.close();
  },
);
```

`count()` reads are billed at one read per 1 000 index entries, not per document — cheap enough nightly.

## Emulator caveat

The Functions emulator registers scheduled functions but **does not run them on a schedule**. Trigger by hand:

- Emulator UI → Functions → the function → "Run" (for scheduled/pubsub functions), or
- POST to the emulator's trigger endpoint: `curl -X POST http://127.0.0.1:5001/<projectId>/<region>/<functionName>` — verify the exact path against the current firebase-tools version; or
- Call the exported handler directly in a test: `await purgeDeletedNotes.run({ scheduleTime: new Date().toISOString(), jobName: "test" } as ScheduledEvent)` — v2 functions expose `.run` for the raw handler (verify against firebase docs; `firebase-functions-test` `wrap` is the documented route).

Production: Cloud Scheduler console lets you "Force run" a job; use it after deploying a new job to verify.

## Monitoring

- Alert if a job has not succeeded in `interval × 2` — Cloud Monitoring on `cloudfunctions.googleapis.com/function/execution_count` filtered by function and status, or write `_meta/jobs/{name}.lastSuccessAt` and have a lightweight `every 1 hours` watchdog that logs an error (→ Error Reporting alert) when any job is overdue.
- Log a structured summary per run (`processed`, `enqueued`, `ms`, `scheduleTime`).

## Does not exist / common mistakes

- `functions.pubsub.schedule("…").timeZone("…").onRun(ctx => …)` — v1. v2 is `onSchedule({ schedule, timeZone }, (event) => …)`.
- Omitting `timeZone` — the job runs in UTC.
- Looping over an unbounded collection inline — hits 540 s and dies half-way with no cursor; chunk through tasks.
- `retryCount` on a non-resumable job — the retry restarts from the beginning and double-applies side effects.
- Expecting the emulator to fire schedules — it never does.
- `maxInstances: 1` as the only overlap guard — set `concurrency: 1` too, or take a lease.
- Using `Date.now()` for "which day is this run for" — use `event.scheduleTime`; a delayed retry at 03:40 is still the 03:00 run.
- Cron with seconds (`0 0 3 * * *`) — Cloud Scheduler is 5-field; six fields fail at deploy.
- A schedule tighter than the job's runtime — overlapping runs; measure before choosing `every 1 minutes`.

# Rollback and incidents

The Firebase CLI has no `rollback` command. The plan is: redeploy the previous tag (minutes), flip a flag to disable the broken path (seconds, if the flag existed before the incident), or stop the function (seconds, ugly). Decide which one before the incident, per function.

## Option 1 — redeploy the previous tag (the default)

```bash
git fetch --tags
git checkout v1.4.1                      # last known good
npm --prefix Server/functions ci
npm --prefix Server/functions run build
cd Server
firebase deploy -P prod --non-interactive --only functions:api:extractText   # narrow to the broken function(s)
```

Or, without a laptop: GitHub Actions → `deploy` → **Run workflow** on the tag `v1.4.1` with `target: prod`; the `production` environment reviewer approves. Prefer this — it is the same path as a normal deploy and leaves an audit trail.

Constraints:

- Rolling back **code** does not roll back **data**. If `v1.4.2` changed a document shape or a rule, check the CHANGELOG entry first; a code rollback that reads a shape the new rules forbid is a second incident.
- Rules and indexes are versioned in git too: `firebase deploy -P prod --only firestore:rules` from the old tag. Rules have a release history in the console (Firestore → Rules → history) where an old version can be restored by hand.
- A rollback deploy of a function is still a Cloud Build (2–5 min). Do not wait for it to decide about the kill switch.
- After rollback, tag the state (`v1.4.3` = revert commit on `main`) so `main` and prod agree again. Never leave prod on a tag that `main` does not contain.

## Option 2 — Cloud Run revision traffic (escape hatch, seconds)

v2 functions are Cloud Run services and keep previous revisions. Traffic can be moved back without a build:

```bash
gcloud run revisions list --service extracttext --region asia-southeast1 --project snaptool-prod
gcloud run services update-traffic extracttext --region asia-southeast1 --project snaptool-prod \
  --to-revisions extracttext-00041-abc=100
```

Caveats (verify against firebase docs before relying on this):

- The Firebase CLI does not manage traffic splits; the next `firebase deploy` sends 100 % to the new revision again. This buys minutes, not a fix.
- Revisions share environment: a rolled-back revision still reads the *current* secret versions and params bound at its own deploy time — usually fine, sometimes not.
- Event-driven functions (Firestore, Storage, Tasks) route through Eventarc/Cloud Tasks to the service, so the traffic switch applies to them as well.

## Option 3 — feature flags (seconds, if prepared)

The cheapest rollback is not deploying. Every expensive or risky path is behind a flag that can be flipped without a deploy.

### Remote Config server-side (firebase-admin ≥ 12.1)

```ts
import { getRemoteConfig } from "firebase-admin/remote-config";

const rc = getRemoteConfig();
const templatePromise = rc.getServerTemplate({ defaultConfig: { ocr_enabled: true, push_enabled: true } });

export async function flags() {
  const template = await templatePromise;
  return template.evaluate();               // ServerConfig; call template.load() to refresh from the backend
}

// in a handler
if (!(await flags()).getBoolean("ocr_enabled")) throw new HttpsError("unavailable", "OCR is temporarily disabled", { retryAfterSeconds: 600 });
```

Flip it in the Firebase console → Remote Config (no deploy). Refresh the template periodically (`setInterval(() => template.load(), 60_000)` at module level is acceptable in a long-lived instance; verify the current API surface against firebase docs — server-side Remote Config is newer than the client APIs). iOS can read the same Remote Config keys to hide the button (`firebase-ios-contract`).

### Firestore flag document (simplest, 1 read per invocation)

```ts
const flagRef = db.doc("config/flags");
let cached: { data: Record<string, boolean>; at: number } | undefined;
export async function flag(name: string, fallback = true) {
  if (!cached || Date.now() - cached.at > 30_000) cached = { data: (await flagRef.get()).data() ?? {}, at: Date.now() };
  return cached.data[name] ?? fallback;
}
```

Writable only by the Admin SDK (rules deny all client writes). Flip with a one-line script or the console. Cost: one read per instance per 30 s.

### Params (`defineBoolean`) — needs a deploy

`PUSH_ENABLED=false` in `.env.snaptool-prod` + `firebase deploy --only functions:sendPush`. A deploy, so minutes not seconds — use params for per-environment defaults, not for incident response.

## Option 4 — stop the function

When a function is burning money or corrupting data and no flag exists:

```bash
# 1. Stop new invocations of a callable: delete it. Clients get functions/not-found; iOS shows its generic error.
firebase functions:delete extractText --region asia-southeast1 -P prod --force

# 2. For a trigger or task worker: delete it (events during the gap are lost) — or throttle first:
#    lower maxInstances/concurrency in code and deploy only that function (minutes).

# 3. For a task queue: pause the queue (seconds), keeps tasks
gcloud tasks queues pause processScan --location asia-southeast1 --project snaptool-prod
gcloud tasks queues resume processScan --location asia-southeast1 --project snaptool-prod

# 4. For a schedule: pause the Cloud Scheduler job (seconds)
gcloud scheduler jobs pause firebase-schedule-nightly-asia-southeast1 --location asia-southeast1 --project snaptool-prod
```

Redeploying after a delete recreates the function; Firestore triggers resume from the moment of creation (no replay). `maxInstances: 0` is not a documented off switch — do not rely on it.

## Incident checklist

**First 5 minutes**

1. Confirm blast radius: Error Reporting (new groups since the deploy), Logs `severity>=ERROR`, instance count, budget spend. Which functions, since which revision, which iOS version (`x-app-version` header if logged).
2. Stop the bleeding in this order: flag → Cloud Run traffic → delete/pause → redeploy tag. Announce in the team channel which one you did.
3. If user data may be corrupted, stop the writer first (delete/pause) and only then think about reads.

**Until resolved**

4. Redeploy the last good tag through the `deploy` workflow (audit trail) or fix forward with `--only functions:<name>` if the fix is one line and tested in the emulator.
5. Watch the four signals from `monitoring.md` for 15 minutes after the change.
6. Data repair: a one-off script under `Server/scripts/` using the Admin SDK with `db.bulkWriter()`, dry-run flag, and a log of every doc touched; run against staging with a copy first (Firestore export/import).

**After**

7. Postmortem in `Server/docs/incidents/YYYY-MM-DD-<slug>.md`: timeline, cause, what detected it (a human or an alert?), what would have made it a non-event.
8. Add the missing thing: a flag for that path, an alert with the threshold that would have fired, a rules test, an emulator integration test that reproduces the bug, a `maxInstances`.
9. If a client change is needed, file it with the oldest affected iOS version and decide whether the server keeps a compatibility shim until that version is below 1 % of traffic.
10. Prune: `functions:secrets:prune`, delete the emergency script's credentials, close the temporary alert channel.

## Practising

Once per quarter on staging: pick a function, "break" it with a deploy that throws, and time the four options. If the flag flip takes longer than a minute because nobody remembers where it is, fix the runbook.

## Does not exist / common mistakes

- `firebase functions:rollback` / `firebase deploy --rollback` — no such command.
- `firebase functions:disable name` — no such command; delete, pause the queue/job, or flag.
- Editing code in the Cloud console inline editor for a hotfix — v2 functions are container images; the console editor is not the source of truth and the next CI deploy overwrites it.
- Rolling back a function while leaving the tightened rules in place (or vice versa) — treat rules + indexes + functions as one release.
- Using `firebase use prod` on a laptop during the incident and forgetting to switch back — always `-P prod`, and prefer the workflow dispatch.
- Deleting a callable that the current App Store build calls when a flag would have done: the delete turns into `functions/not-found` for every user until redeploy; a flag returns `unavailable` with a message the client can display.

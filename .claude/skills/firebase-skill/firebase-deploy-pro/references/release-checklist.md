# Release checklist

Run top to bottom before tagging `vX.Y.Z`. Every line is a yes/no. A "no" is either fixed or written into the CHANGELOG entry as a known deviation with a reason. Copy this into the PR description for the release commit.

## A. Code and contract

- [ ] `npm run lint` and `npm run build` clean on `main`; no `@ts-ignore` added this release.
- [ ] Every new/changed callable validates `request.data` with zod and throws `HttpsError` with a stable code; no raw `throw new Error` reaches the client.
- [ ] Every new/changed callable is backward-compatible with the **oldest supported iOS build**: new request fields optional, removed fields still accepted, response only gained fields. (`deploy-workflow.md` → ordering table.)
- [ ] No function renamed, region-moved, or deleted in this release — or the three-step plan is at the right step and the CHANGELOG says which.
- [ ] Firestore `Timestamp` never returned from a callable (ISO strings / millis).
- [ ] Triggers touched this release are idempotent (`event.id` marker or `ref.create`) and guard against re-firing on their own writes.
- [ ] `.value()` on params/secrets only inside handlers (`grep -n "\.value()" src` reviewed).
- [ ] No `functions.config()`, no `firebase-functions/v1` import except the documented Auth lifecycle triggers, no `sendMulticast`/`sendAll`.

## B. Tests (from `firebase-testing-pro`)

- [ ] `functions-test` workflow green on the release commit: unit, rules, integration under `emulators:exec`.
- [ ] Every changed `match` block in `firestore.rules` / `storage.rules` has a new passing and a new failing test.
- [ ] Every new callable has one integration test asserting the error code on the wire for the unauthenticated case.
- [ ] Rules coverage JSON shows no new `allow` line with zero evaluations.
- [ ] iOS UI test plan `UITests-Emulator` passed against this server build (or the release touches nothing the app calls).

## C. Configuration

- [ ] `firebase.json` `runtime` and `package.json` `engines.node` agree (`nodejs22` / `"22"`).
- [ ] New params have a default **or** a value in every `.env.<projectId>` (`.env.snaptool-staging`, `.env.snaptool-prod`).
- [ ] New secrets set in **both** staging and prod: `firebase functions:secrets:access NAME -P staging` and `-P prod` succeed.
- [ ] New `firestore.indexes.json` entries were deployed to staging days ago and are `READY` in prod before the client ships (`firebase firestore:indexes -P prod` or console).
- [ ] Storage lifecycle / Firestore TTL policies exist for any new collection with unbounded growth.
- [ ] Any new `onSchedule` → Cloud Scheduler job count and quota checked; `timeZone` set explicitly.
- [ ] Any new task queue → Cloud Tasks API enabled in prod; `retryConfig` and `rateLimits` set.

## D. Caps and cost (from `cost.md`)

- [ ] Every new function has `maxInstances` and `timeoutSeconds` (explicit or via `setGlobalOptions`); AI/FCM fan-out functions have explicit lower values.
- [ ] Per-user quota in place for any new paid-API path.
- [ ] `minInstances` unchanged, or the monthly cost of the change is in the CHANGELOG.
- [ ] Image/input size limits enforced in rules and in the handler.
- [ ] Budget thresholds still appropriate if this release is expected to change traffic.

## E. Monitoring (from `monitoring.md`)

- [ ] New functions log `<name>.start` / `<name>.failed` structured events with `uid` and entity id; no PII, prompts, or tokens in logs.
- [ ] Alerting policies cover the new function's service name (policies group by `service_name`; nothing to do if they are project-wide — confirm).
- [ ] `/health` untouched or still cheap and public; uptime check green in staging.
- [ ] A log-based metric exists for any new paid-API call's usage field.

## F. Security

- [ ] `enforceAppCheck: true` on every new callable the iOS app calls; `consumeAppCheckToken` on sensitive ones with the client using limited-use tokens.
- [ ] `request.auth` checked before any per-user read/write; custom claims checked for admin paths.
- [ ] Rules deny by default (`match /{document=**} { allow read, write: if false; }` still last).
- [ ] No new `invoker: "public"` `onRequest` besides `/health`; any webhook verifies a signature.
- [ ] Secrets not logged, not in `.env*`, not in GitHub secrets.
- [ ] Account-deletion path still works (Delete User Data extension or v1 `onDelete` trigger) if Auth or data layout changed.

## G. Staging soak

- [ ] Deployed to staging from `main` by CI; smoke test passed.
- [ ] Manual pass on a TestFlight/Staging build of the iOS app for each changed feature, including the error path (airplane mode, quota reached).
- [ ] Error Reporting on staging: no new groups in 24 h (or explained).
- [ ] Latency/instances charts for changed functions unremarkable.

## H. Release mechanics

- [ ] `CHANGELOG.md` entry: functions added/removed/renamed, rules/index changes, params/secrets added, manual steps, rollback notes ("safe to roll back to v1.4.1: yes/no, why").
- [ ] `functions/package.json` version bumped; tag `vX.Y.Z` on the release commit on `main`.
- [ ] A reviewer for the `production` environment is available for the next hour, and a second person knows the rollback path (`rollback-and-incidents.md`).
- [ ] Not a Friday afternoon, not during the iOS App Review window for a dependent client release, unless the change is server-first and backward-compatible (it should be).

## I. Post-deploy (first 30 minutes)

- [ ] Workflow summary shows the tag and SHA; `firebase functions:list -P prod` matches expectations (no unexpected deletions).
- [ ] `/health` returns the new `revision`.
- [ ] Error Reporting: no new groups. Logs `severity>=ERROR`: nothing new.
- [ ] 5xx ratio, p95 latency, active instances flat.
- [ ] One real callable exercised from a prod iOS build (your own device) for each changed feature.
- [ ] Budget dashboard unchanged after 24 h; log-based usage metrics within expected range.

## Rollback decision before you deploy

Write the answer into the CHANGELOG entry; it is the first thing the on-call reads.

| Question | If yes |
|---|---|
| Does this release change a Firestore document shape? | Server writes both shapes for one client release cycle; rollback to previous tag is **safe** only while both shapes are written. |
| Does it tighten `firestore.rules` / `storage.rules`? | Rules rollback = redeploy `--only firestore:rules` from the previous tag; note the release id in the console's rules history. |
| Does it delete or rename a function? | Rollback must recreate it: previous tag + `--only functions:<old-name>`; clients on the old name recover only after that. |
| Does it add a required param or secret? | The previous tag does not read it; rollback is safe. The reverse (rolling *forward* again) needs the value present — it is. |
| Does it add an index the client depends on? | Rollback of code is safe; never delete the index during rollback. |
| Does it change `region` of anything? | Treat as rename; rollback follows the three-step plan in reverse. |
| Is there a flag to disable the new path without a deploy? | Say which key (`ocr_v2_enabled`) and where (Remote Config / `config/flags`). If no, add one before tagging when the path is paid or risky. |

## Sign-off

| Role | Confirms |
|---|---|
| Author | sections A–D, and the CHANGELOG entry |
| Reviewer (PR) | contract compatibility with the oldest supported iOS build; rules tests present |
| `production` environment approver | staging soak (G) done, rollback decision written, someone is on watch for 30 min |

Two people minimum for prod; the same person cannot be author and environment approver.

## Automate what can be automated

Each of these turns a checkbox into a CI failure, which is the only reliable form of a checklist:

- A–B: the `functions-test` workflow (lint, build, emulator tests) as a required status check on `main`.
- C (runtime agreement): a one-line script in `predeploy` that diffs `firebase.json` `runtime` against `engines.node` and exits 1 on mismatch.
- C (params/secrets present): `predeploy` step that greps `defineString|defineInt|defineBoolean|defineSecret` names from `src/` and checks each has a default or a line in `.env.<target project>`; for secrets, `firebase functions:secrets:access NAME -P <alias> > /dev/null`.
- D (`maxInstances` everywhere): an ESLint rule or a grep in CI that fails when `onCall(`/`onRequest(`/`onTaskDispatched(` appears without a `maxInstances` key and `setGlobalOptions` does not set one.
- E (log conventions): a lint rule forbidding `console.log` in `src/`.
- H (tag ↔ version): the `deploy-prod` job asserts `github.ref_name == "v" + package.json.version` before deploying.

What remains manual — contract review against the oldest iOS build, the rollback decision, and the staging soak — is the part worth a human's time.

## Minimal version (hotfix, single function)

1. Fix on a branch, emulator test reproduces the bug and passes.
2. Merge to `main` → staging deploy → smoke.
3. Tag `vX.Y.(Z+1)`; CHANGELOG: one line + rollback note.
4. Approve `deploy-prod`; it deploys everything, which is fine because `main` is otherwise unchanged — or `workflow_dispatch` with a narrowed `--only` if the deploy step supports an input for it.
5. Post-deploy checks A–D above for that function only.

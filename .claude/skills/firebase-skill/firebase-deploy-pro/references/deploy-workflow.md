# Deploy workflow

A deploy is: build → test → deploy rules/indexes → deploy functions, scoped with `--only`, from CI, from a git ref. This file covers the commands, partial deploys, the dangerous operations (delete, rename, region move), ordering against iOS releases, and what to do when a deploy dies halfway.

## The standard sequence

```bash
# scripts/deploy.sh <alias>
set -euo pipefail
ALIAS="${1:?usage: deploy.sh <staging|prod>}"
cd "$(dirname "$0")/.."                      # Server/

npm --prefix functions ci
npm --prefix functions run lint
npm --prefix functions run build
npm --prefix functions run test:pure         # emulator tests ran in the test job already

# 1. Rules first: a compile error aborts before anything changes.
firebase deploy -P "$ALIAS" --non-interactive --only firestore:rules,storage
# 2. Indexes: start building now; they take minutes.
firebase deploy -P "$ALIAS" --non-interactive --only firestore:indexes
# 3. Functions, one codebase at a time.
firebase deploy -P "$ALIAS" --non-interactive --only functions:api
firebase deploy -P "$ALIAS" --non-interactive --only functions:ai
```

`--non-interactive` makes every prompt an error instead of a hang. Prompts you will hit and how to pre-answer them:

| Prompt | Cause | Pre-answer |
|---|---|---|
| "The following functions are found in your project but do not exist in your local source code … Would you like to proceed with deletion?" | an export was removed | `--force` (deletes them) — only after the plan below |
| "Would you like to delete these indexes?" | index removed from `firestore.indexes.json` | `--force` |
| "Enter a value for PARAM" | a `defineString` with no default and no `.env.<project>` value | add the value; never `--force` past this |
| "Enable API x?" | new project | pre-enable with `gcloud services enable` |

`--force` therefore means "yes, delete what is missing". Use it on staging freely and on prod only in a deploy that intentionally removes functions.

## `--only` targets

```bash
firebase deploy -P prod --only functions                        # every codebase
firebase deploy -P prod --only functions:api                    # one codebase
firebase deploy -P prod --only functions:api:createNote         # one function in a codebase
firebase deploy -P prod --only functions:createNote,functions:sendPush
firebase deploy -P prod --only "functions:notes.*"              # NOT supported — no wildcards; list names
firebase deploy -P prod --only firestore:rules
firebase deploy -P prod --only firestore:indexes
firebase deploy -P prod --only storage
firebase deploy -P prod --only firestore,storage,functions:api
```

Grouped exports narrow further: `export const notes = { create: onCall(...), share: onCall(...) }` deploys as `notes-create`, `notes-share` and `--only functions:notes` deploys the group.

A `--only functions:<name>` deploy does **not** delete other functions and does not prompt about them — that is the safe form for hotfixes.

## What `firebase deploy --only functions` actually does (v2)

1. Runs `predeploy`, zips `source` minus `ignore`, uploads to a Cloud Storage staging bucket.
2. Loads the code once with `FUNCTIONS_CONTROL_API=true` to discover exports and their options (this is where a top-level `secret.value()` or a network call at import breaks the deploy).
3. Cloud Build builds a container per codebase (Artifact Registry stores the image).
4. Creates/updates each function as a Cloud Run service (name lowercased, e.g. `createnote`) plus its Eventarc trigger / Cloud Scheduler job / Cloud Tasks queue.
5. Deletes functions missing from the source (with prompt / `--force`).

Steps 4–5 are per function and **not atomic**. A deploy of 20 functions can succeed for 17 and fail for 3.

## When a deploy fails halfway

```
✔  functions[api:createNote(asia-southeast1)] Successful update operation.
✖  functions[api:sendPush(asia-southeast1)] Deployment error.
   ... Build failed / quota exceeded / ...
```

1. Read the error. Common ones:
   - `Build failed` → open the Cloud Build log link; usually a missing runtime dep or a TypeScript emit problem.
   - `Quota exceeded for quota metric 'Per project mutation requests'` → too many functions at once; redeploy the failed subset.
   - `Container Healthcheck failed` / `The user-provided container failed to start and listen on the port` → the module throws at import (secret read at top level, `initializeApp()` twice, a missing `.env` key).
   - `Permission denied on secret` → the runtime service account lacks `roles/secretmanager.secretAccessor` on that secret in this project.
   - `Eventarc trigger … region` → Firestore trigger deployed to a region its database does not support.
2. The functions that succeeded are live on the new code. The failed ones are still on the **old** code. If the new code depends on the new client contract, this is a mixed state — decide fast:
   - Fix forward: `firebase deploy -P prod --only functions:sendPush` with the fix.
   - Roll back the succeeded ones: `git checkout <previous-tag>` and `--only functions:createNote,...` (see `rollback-and-incidents.md`).
3. Never re-run the full deploy blindly with `--force`; a half-failed deploy plus `--force` can delete functions whose export failed to *load*, not just ones you removed.
4. `firebase functions:list -P prod` shows what is deployed with runtime and region — compare against the source.

## Deleting a function

Removing the export and deploying prompts for deletion. Do it deliberately:

```bash
firebase functions:delete sendPushLegacy --region asia-southeast1 -P prod --force
```

Before deleting: confirm with Cloud Logging that the function had zero invocations for a period longer than the oldest supported iOS version's age (`resource.labels.service_name="sendpushlegacy"` — see `monitoring.md`). Deleting a function that an old client still calls turns into `functions/not-found` on their device forever.

For triggers, deleting is safe immediately (no client calls them) but events during the gap are lost — for Firestore triggers that matter, deploy the replacement first.

## Renaming a function (or a callable's name)

Renaming is delete + create; the URL changes. Three deploys, spread over the iOS adoption curve:

1. **Deploy new name** alongside the old: `export const createNoteV2 = ...; export const createNote = createNoteV2;` — or two exports sharing one handler. Both live.
2. **Ship the iOS client** calling the new name. Wait until the old name's invocation count is ~0 (weeks).
3. **Delete the old export** and deploy with `--force` (or `functions:delete`).

Never rename a callable that the App Store build calls in one step. Never rename a Firestore-triggered function's *export* casually either — the trigger is re-created, and events between delete and create are dropped.

## Moving a function to another region

Region is part of the identity; changing `region` in options deploys a new function and prompts to delete the old one. Same three-step plan as renaming, with the client's `Functions.functions(region:)` changed in step 2. For Firestore triggers, the new region must be one the database supports. Plan region up front — moving Firestore's own region is impossible (new database + migration).

## Ordering with iOS releases

| Change | Order |
|---|---|
| New optional response field | server first (any time) |
| New required request field | server accepts both shapes first → client → server tightens after adoption |
| New callable | server first; client can ship the same day |
| Renamed / removed callable | 3-step plan above |
| Firestore document shape change | rules + indexes → server writes both shapes → client reads new → server stops writing old |
| Security-rules tightening | verify with rules tests that the **oldest supported client's** writes still pass; deploy rules first |
| New composite index | deploy indexes days before the client that queries |

A server deploy must never require a client update to keep working. The reverse is fine: a client update may require a server that is already deployed. Encode this as a version check only when unavoidable: `request.rawRequest.headers["x-app-version"]` with a `failed-precondition` error the client maps to "please update" — see `firebase-ios-contract`.

## Tags and the CHANGELOG

- Every prod deploy comes from a tag `v<major>.<minor>.<patch>` on `main`. CI creates the deploy from the tag; nobody deploys from a branch.
- `CHANGELOG.md` entry per tag: functions added/removed/renamed, rules changes, index changes, param/secret changes, required manual steps.
- Rollback target is the previous tag; if the previous tag included a schema change, the CHANGELOG says whether rolling back is safe.

## Local deploys (dev project only)

`firebase deploy -P default --only functions:api` from a laptop to `snaptool-dev` is fine and normal. Deploying to staging or prod from a laptop is not: the WIF binding in `github-actions.md` is the only principal with deploy rights on those projects.

## Does not exist / common mistakes

- `firebase deploy --only functions --force` as the default in CI — it also deletes; use `--force` only in a deploy whose CHANGELOG entry lists the deletions.
- `firebase deploy --only functions:api --region asia-southeast1` — no `--region` flag on deploy; region comes from function options.
- `firebase functions:delete` without `--region` on a multi-region project — prompts; pass it.
- Deploying `firestore:indexes` after the function that needs the index — `FAILED_PRECONDITION` until the build finishes.
- `firebase deploy` with the `hosting` section present but no `public/` dir — prompts. Remove unused sections.
- Relying on the "deployed at" time in the console to know which commit is live — set a `RELEASE` param from CI (`echo "RELEASE=${GITHUB_SHA}" >> functions/.env.snaptool-prod` before deploy is wrong: it dirties the repo). Log `process.env.K_REVISION` instead and keep the CI run ↔ tag mapping in GitHub.
- `--only functions` while another deploy of the same project is running (two CI jobs) — Cloud Run update conflicts. Use a `concurrency` group per environment in GitHub Actions.

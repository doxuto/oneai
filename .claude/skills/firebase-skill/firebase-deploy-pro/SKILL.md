---
name: firebase-deploy-pro
description: Writes, reviews, and fixes the environment, deploy, CI/CD, monitoring, and cost setup for Firebase Cloud Functions (2nd gen, TypeScript) backing an iOS app. Use when working with firebase deploy, firebase.json, .firebaserc, firebase use, codebase, multi-environment or staging/production projects, GitHub Actions, Workload Identity Federation, rollback, functions:log, Cloud Logging, Error Reporting, alerting policies, budget alerts, maxInstances, minInstances, or Cloud Functions cost.
license: MIT
metadata:
  author: doxuto
  version: "1.0"
  targets: "firebase-functions 6.x (v2), firebase-admin 13.x, Node 22, Firebase iOS SDK 12.x"
---

Set up and review how a Firebase Functions backend is configured per environment, deployed, observed, and kept within budget — so that a deploy is boring, a bad deploy is reversible in minutes, and a runaway function cannot empty the billing account. Report only genuine problems — do not nitpick or invent issues.

## Core principles

1. **One Firebase project per environment.** `dev`, `staging`, `prod` are separate projects with separate Firestore, Auth users, secrets, APNs keys and budgets. Sharing a project between dev and prod is the root cause of most "we deleted real users" stories.
2. **Everything that differs per environment is a param, a secret, or a `.firebaserc` alias.** Never an `if (projectId === "snaptool-prod")` in code.
3. **Deploy is a build artifact of a git ref.** CI deploys `main` to staging and a `v*` tag to prod. Nobody runs `firebase deploy -P prod` from a laptop. Rollback is redeploying the previous tag.
4. **Server first, backward-compatible.** iOS releases sit in review for days and old versions live for months. Every function change must accept the previous client's payload; remove old fields only after the client's adoption curve says so.
5. **Observe before you optimise.** Structured `logger` fields, Error Reporting, and three alerting policies (error rate, latency, instance count) come with the first deploy, not after the first incident.
6. **Caps before growth.** `maxInstances`, `timeoutSeconds`, per-user quotas and a budget alert are set on day one. A cost overrun is a missing cap, not bad luck.

## Review process

1. Check project aliases, `.env.<project>` params, secrets, and the iOS `GoogleService-Info.plist` per configuration using `references/environments.md`.
2. Check `firebase.json` — codebases, runtime, predeploy hooks, rules/indexes paths, ignore patterns — using `references/firebase-json.md`.
3. Check the deploy commands, partial deploys, function delete/rename/region-move plans, and client-release ordering using `references/deploy-workflow.md`.
4. Check the GitHub Actions workflow — WIF auth, test gate, staging on `main`, prod on tag with approval — using `references/github-actions.md`.
5. Check logging, Error Reporting, alerting policies, uptime checks, and log-based metrics using `references/monitoring.md`.
6. Check pricing levers, budget alerts, `maxInstances`, Firestore read amplification and Gemini token spend using `references/cost.md`.
7. Check the rollback path, kill switches, and the incident checklist using `references/rollback-and-incidents.md`.
8. Walk the pre-deploy list in `references/release-checklist.md` before any production deploy.

If doing a partial review, load only the relevant reference files.

## Core instructions

- Target firebase-tools 14.x, firebase-functions 6.x (v2), firebase-admin 13.x, Node 22 (`"engines": { "node": "22" }` and `"runtime": "nodejs22"` must agree).
- `.firebaserc` declares `default` (dev), `staging`, `prod`. Every CLI command in scripts and CI passes `-P <alias>` explicitly; never rely on the current `firebase use`.
- Per-environment values go in `functions/.env.<projectId>` (params via `defineString` / `defineInt` / `defineBoolean`) and in Secret Manager (`firebase functions:secrets:set NAME -P <alias>`). Never `functions.config()`; never a secret in `.env`.
- `firebase.json` functions entries set `codebase`, `runtime: "nodejs22"`, a `predeploy` that runs lint + build, and `ignore` for `node_modules`, `.git`, `*.local`, `*-debug.log`, `test/`.
- Every deploy command is `--only`-scoped and `--non-interactive` in CI (`--force` only where the reference file says it is safe).
- Deleting or renaming a function, or moving its region, follows the three-step plan in `deploy-workflow.md` (deploy new → migrate clients → delete old). Never rename in one deploy.
- Firestore rules and indexes deploy **before** the functions and the app that depend on them: `--only firestore:rules,firestore:indexes` first, then `--only functions`.
- CI authenticates with Workload Identity Federation (`google-github-actions/auth@v2`); no service-account JSON and no `FIREBASE_TOKEN` in GitHub secrets.
- Prod deploys run only from a `v*` tag, in a GitHub `environment` with required reviewers, with `concurrency` so two deploys never overlap.
- Every function sets `maxInstances`; the global default via `setGlobalOptions` and a lower explicit value on anything that calls Gemini, Vision, or FCM fan-out.
- Alerting policies exist for: 5xx / error rate > 2 % over 5 min, p95 latency over the function's budget, active instances near `maxInstances`, and a Cloud Billing budget at 50 / 90 / 100 %.
- Every `onRequest` health endpoint (`/health`) is unauthenticated, cheap, and has an uptime check in staging and prod.
- No environment-specific logic in code: no `if (process.env.GCLOUD_PROJECT === ...)`; read a param instead.
- Keep a `CHANGELOG` entry and a git tag for every prod deploy so rollback is `git checkout vX.Y.Z && deploy`.

## Canonical example

The minimum set of files for a three-environment backend with a safe deploy.

```json
// .firebaserc
{ "projects": { "default": "snaptool-dev", "staging": "snaptool-staging", "prod": "snaptool-prod" } }
```

```json
// firebase.json
{
  "functions": [
    {
      "source": "functions",
      "codebase": "api",
      "runtime": "nodejs22",
      "predeploy": ["npm --prefix \"$RESOURCE_DIR\" run lint", "npm --prefix \"$RESOURCE_DIR\" run build"],
      "ignore": ["node_modules", ".git", "firebase-debug.log", "firebase-debug.*.log", "*.local", "test", "coverage"]
    }
  ],
  "firestore": { "rules": "firestore.rules", "indexes": "firestore.indexes.json" },
  "storage": { "rules": "storage.rules" },
  "emulators": {
    "functions": { "port": 5001 }, "firestore": { "port": 8080 }, "auth": { "port": 9099 },
    "storage": { "port": 9199 }, "ui": { "enabled": true, "port": 4000 }, "singleProjectMode": true
  }
}
```

```
# functions/.env                 (shared defaults, committed)
REGION=asia-southeast1
OCR_DAILY_QUOTA=20
# functions/.env.snaptool-prod   (committed; non-secret overrides)
OCR_DAILY_QUOTA=100
SENTRY_ENV=production
# functions/.env.snaptool-staging
SENTRY_ENV=staging
```

```ts
// functions/src/index.ts — params, global caps, a health endpoint, one guarded callable
import { setGlobalOptions } from "firebase-functions/v2";
import { onCall, onRequest, HttpsError } from "firebase-functions/v2/https";
import { defineInt, defineSecret, defineString } from "firebase-functions/params";
import { logger } from "firebase-functions";
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore, FieldValue } from "firebase-admin/firestore";

const REGION = defineString("REGION", { default: "asia-southeast1" });
const OCR_DAILY_QUOTA = defineInt("OCR_DAILY_QUOTA", { default: 20 });
const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

setGlobalOptions({ region: "asia-southeast1", maxInstances: 20, timeoutSeconds: 60, memory: "256MiB" });

if (getApps().length === 0) initializeApp();
const db = getFirestore();

export const health = onRequest({ invoker: "public", maxInstances: 2, memory: "128MiB" }, (_req, res) => {
  res.status(200).json({ ok: true, version: process.env.K_REVISION ?? "local" });
});

export const extractText = onCall(
  { enforceAppCheck: true, secrets: [GEMINI_API_KEY], maxInstances: 5, timeoutSeconds: 120, memory: "1GiB" },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required");

    const today = new Date().toISOString().slice(0, 10);
    const quotaRef = db.doc(`users/${uid}/quotas/${today}`);
    const used = await db.runTransaction(async (tx) => {
      const snap = await tx.get(quotaRef);
      const n = (snap.data()?.ocr ?? 0) + 1;
      if (n > OCR_DAILY_QUOTA.value()) throw new HttpsError("resource-exhausted", "Daily OCR quota reached", { quota: OCR_DAILY_QUOTA.value() });
      tx.set(quotaRef, { ocr: FieldValue.increment(1), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
      return n;
    });

    logger.info("extractText.start", { uid, used, region: REGION.value(), revision: process.env.K_REVISION });
    // ... call Gemini with GEMINI_API_KEY.value() (see firebase-functions-pro for the AI half)
    return { used };
  },
);
```

```bash
# scripts/deploy-staging.sh — what CI runs on main; identical shape for prod with -P prod
set -euo pipefail
firebase deploy -P staging --non-interactive --only firestore:rules,firestore:indexes,storage
firebase deploy -P staging --non-interactive --only functions:api
```

Swift side: the iOS project has three build configurations (`Debug`, `Staging`, `Release`) with a bundle id suffix each (`.dev`, `.staging`, none) and a matching `GoogleService-Info.plist` copied by a run-script phase — see `references/environments.md`. The app never chooses a project at runtime.

## Output format

If the user asks for a review, organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated.
3. Show a brief before/after fix.

Skip files with no issues. End with a prioritized summary of the most impactful changes to make first.

If the user asks you to write or improve configuration, follow the same rules but make the changes directly instead of returning a findings report.

Example output:

### .github/workflows/deploy.yml

**Line 18: Service-account JSON stored as a GitHub secret — long-lived credential in CI.**

```yaml
# Before
- run: echo '${{ secrets.GCP_SA_KEY }}' > sa.json
- run: GOOGLE_APPLICATION_CREDENTIALS=sa.json npx firebase deploy -P prod --only functions

# After
permissions: { id-token: write, contents: read }
- uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: projects/123456789/locations/global/workloadIdentityPools/github/providers/github
    service_account: firebase-deployer@snaptool-prod.iam.gserviceaccount.com
- run: npx firebase deploy -P prod --only functions:api --non-interactive
```

### functions/src/index.ts

**Line 9: No `maxInstances` on a function that calls Gemini — a retry storm bills without limit.**

```ts
// Before
export const extractText = onCall({ secrets: [GEMINI_API_KEY] }, handler);

// After
export const extractText = onCall({ secrets: [GEMINI_API_KEY], maxInstances: 5, timeoutSeconds: 120 }, handler);
```

### Summary

1. **Credential hygiene (high):** replace the SA key with Workload Identity Federation.
2. **Cost cap (high):** add `maxInstances` to every AI-calling function and a global default.

End of example.

## References

- `references/environments.md` — dev/staging/prod projects, `.firebaserc` aliases, `.env.<project>` params, per-project secrets, and the iOS `GoogleService-Info.plist` per Xcode configuration.
- `references/firebase-json.md` — annotated `firebase.json`: functions codebases, runtime, predeploy, ignore patterns, firestore rules/indexes, storage, emulators.
- `references/deploy-workflow.md` — build → test → `deploy --only`, partial deploys, deleting / renaming / moving functions safely, deploy ordering with iOS releases, `--force` and `--non-interactive`, recovering from a half-failed deploy.
- `references/github-actions.md` — full workflow: WIF auth, Node 22, lint, `emulators:exec` tests, staging on `main`, prod on tag with a reviewed environment, secrets handling.
- `references/monitoring.md` — structured logs, `functions:log`, Cloud Logging queries for v2, Error Reporting, alerting policies, uptime check on `/health`, log-based metrics.
- `references/cost.md` — pricing levers (invocations, CPU/GB-seconds, egress, min instances, Firestore reads, FCM, Gemini tokens), budget alerts, `maxInstances` as circuit breaker, cost review checklist.
- `references/rollback-and-incidents.md` — redeploying a tag, Cloud Run revision escape hatch, feature flags via params / Remote Config, stopping a runaway function, post-incident checklist.
- `references/release-checklist.md` — the pre-deploy checklist for staging and production.

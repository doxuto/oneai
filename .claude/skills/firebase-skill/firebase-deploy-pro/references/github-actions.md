# GitHub Actions — test, deploy staging, deploy prod

Two workflows: `functions-test.yml` (from `firebase-testing-pro` → `references/ci.md`) gates everything; `deploy.yml` below deploys `main` to staging and `v*` tags to prod behind a reviewed environment. Authentication is Workload Identity Federation — no JSON keys, no `FIREBASE_TOKEN`.

## One-time GCP setup per project (staging and prod)

```bash
PROJECT=snaptool-prod
PROJECT_NUMBER=$(gcloud projects describe $PROJECT --format='value(projectNumber)')
REPO=doxuto/snaptool-server

# 1. Deployer service account
gcloud iam service-accounts create firebase-deployer --project $PROJECT --display-name "CI deployer"
SA=firebase-deployer@$PROJECT.iam.gserviceaccount.com

# 2. Roles the Firebase CLI needs to deploy functions v2 + rules + indexes.
#    Start with this set; add on a specific permission error rather than granting Owner.
#    Verify against firebase docs ("Deploy from CI" / required roles) when the CLI version changes.
for ROLE in roles/cloudfunctions.developer roles/run.admin roles/iam.serviceAccountUser \
            roles/firebaserules.admin roles/datastore.indexAdmin roles/secretmanager.viewer \
            roles/artifactregistry.writer roles/cloudbuild.builds.editor roles/cloudscheduler.admin \
            roles/eventarc.admin roles/storage.admin roles/firebase.viewer; do
  gcloud projects add-iam-policy-binding $PROJECT --member "serviceAccount:$SA" --role $ROLE
done

# 3. Workload Identity pool + GitHub provider
gcloud iam workload-identity-pools create github --project $PROJECT --location global
gcloud iam workload-identity-pools providers create-oidc github --project $PROJECT --location global \
  --workload-identity-pool github --issuer-uri https://token.actions.githubusercontent.com \
  --attribute-mapping "google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.ref=assertion.ref" \
  --attribute-condition "assertion.repository == '$REPO'"

# 4. Let this repo impersonate the deployer
gcloud iam service-accounts add-iam-policy-binding $SA --project $PROJECT \
  --role roles/iam.workloadIdentityUser \
  --member "principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github/attribute.repository/$REPO"

echo "provider: projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/github/providers/github"
```

For prod, tighten the binding to tags only: member `…/attribute.ref/refs/tags/v1.2.3` cannot be wildcarded, so instead add `assertion.ref.startsWith('refs/tags/v')` to the **prod provider's** `--attribute-condition`. Staging's condition allows `refs/heads/main`.

The runtime service account of the functions (default `PROJECT_NUMBER-compute@developer.gserviceaccount.com` for v2) needs `roles/secretmanager.secretAccessor` on each secret; `firebase functions:secrets:set` grants it on deploy — verify in IAM if a function logs `Permission denied on secret`.

## `deploy.yml`

```yaml
name: deploy

on:
  push:
    branches: [main]          # → staging
    tags: ["v*"]              # → prod
  workflow_dispatch:
    inputs:
      target:
        description: staging | prod
        required: true
        default: staging

permissions:
  contents: read
  id-token: write             # required for WIF

defaults:
  run:
    working-directory: Server

env:
  NODE_VERSION: "22"
  FIREBASE_TOOLS_VERSION: "14"

jobs:
  test:
    uses: ./.github/workflows/functions-test.yml      # reusable: the emulator gate from firebase-testing-pro/ci.md

  deploy-staging:
    needs: test
    if: github.ref == 'refs/heads/main' || (github.event_name == 'workflow_dispatch' && inputs.target == 'staging')
    runs-on: ubuntu-latest
    timeout-minutes: 30
    environment: staging
    concurrency:
      group: deploy-staging
      cancel-in-progress: false      # never cancel a deploy mid-flight
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: "${{ env.NODE_VERSION }}", cache: npm, cache-dependency-path: Server/functions/package-lock.json }
      - uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ vars.WIF_PROVIDER_STAGING }}
          service_account: ${{ vars.DEPLOYER_SA_STAGING }}
      - run: npm --prefix functions ci
      - run: npm --prefix functions run lint
      - run: npm --prefix functions run build
      - name: Deploy rules, indexes, storage
        run: npx firebase-tools@${{ env.FIREBASE_TOOLS_VERSION }} deploy -P staging --non-interactive --only firestore:rules,firestore:indexes,storage
      - name: Deploy functions
        run: npx firebase-tools@${{ env.FIREBASE_TOOLS_VERSION }} deploy -P staging --non-interactive --force --only functions
      - name: Smoke test
        # v2 functions keep a stable cloudfunctions.net URL alongside the run.app one
        run: curl -sf "https://asia-southeast1-snaptool-staging.cloudfunctions.net/health" | grep '"ok":true'

  deploy-prod:
    needs: test
    if: startsWith(github.ref, 'refs/tags/v') || (github.event_name == 'workflow_dispatch' && inputs.target == 'prod')
    runs-on: ubuntu-latest
    timeout-minutes: 30
    environment: production          # required reviewers configured in repo settings → Environments
    concurrency:
      group: deploy-prod
      cancel-in-progress: false
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: "${{ env.NODE_VERSION }}", cache: npm, cache-dependency-path: Server/functions/package-lock.json }
      - uses: google-github-actions/auth@v2
        with:
          workload_identity_provider: ${{ vars.WIF_PROVIDER_PROD }}
          service_account: ${{ vars.DEPLOYER_SA_PROD }}
      - run: npm --prefix functions ci
      - run: npm --prefix functions run build
      - name: Deploy rules, indexes, storage
        run: npx firebase-tools@${{ env.FIREBASE_TOOLS_VERSION }} deploy -P prod --non-interactive --only firestore:rules,firestore:indexes,storage
      - name: Deploy functions (no --force: deletions are a separate, reviewed deploy)
        run: npx firebase-tools@${{ env.FIREBASE_TOOLS_VERSION }} deploy -P prod --non-interactive --only functions
      - name: Record release
        run: echo "Deployed ${{ github.ref_name }} (${{ github.sha }}) to snaptool-prod" >> "$GITHUB_STEP_SUMMARY"
```

Notes:

- `vars.*` are repository/environment **variables** (non-secret): the WIF provider resource name and the SA email are not secrets. The `production` environment can hold its own values so the staging job cannot see prod's.
- `google-github-actions/auth@v2` writes an ADC credentials file and exports `GOOGLE_APPLICATION_CREDENTIALS`; firebase-tools picks it up automatically. No `firebase login`, no token.
- `needs: test` on both deploy jobs: a red emulator run blocks the deploy. With the test workflow as `workflow_call`, add `on: workflow_call:` to `functions-test.yml`.
- Staging uses `--force` so removed functions disappear automatically. Prod does not: a deploy that must delete functions is run once with `workflow_dispatch` after the CHANGELOG lists the deletions, or by a dedicated `functions:delete` step in a PR-reviewed change.
- `cancel-in-progress: false` on deploy groups. A cancelled deploy is a half-deploy.
- The smoke test calls `/health`; extend it with one authenticated callable via the web SDK against staging if the project has a CI test user (create it with the Admin SDK inside the job — the deployer SA can be granted `roles/firebaseauth.admin` for staging only).

## Tagging a release

```bash
git checkout main && git pull
npm --prefix Server/functions version minor --no-git-tag-version   # bumps package.json
git commit -am "release: v1.4.0" && git tag v1.4.0 && git push && git push --tags
```

The tag push triggers `deploy-prod`; the `production` environment holds it until a reviewer approves in the Actions UI. Approving is the deploy.

## Secrets handling in CI — what goes where

| Thing | Where | Not |
|---|---|---|
| Gemini key, third-party API keys | Secret Manager via `functions:secrets:set` (once, by hand) | GitHub secrets, `.env*` |
| WIF provider, SA email | GitHub environment variables | secrets (they are not sensitive) |
| Per-environment non-secret config | `functions/.env.<projectId>` in git | GitHub variables (drifts from the repo) |
| Test users' passwords for the smoke test | GitHub environment secret, staging only | prod |
| `FIREBASE_TOKEN` | nowhere — `firebase login:ci` tokens are deprecated | |

A secret referenced in code but not set in the target project fails at deploy with a clear error; the release checklist has a step for it.

## PR workflow (no deploy)

`functions-test.yml` runs on every PR and nothing deploys. There is no `firebase deploy --dry-run` flag. The pre-flight that catches most deploy-time failures is already in the test job: `npm run build` plus the Functions emulator loading `lib/` — the emulator executes the same export-discovery path as the deploy, so a module that throws at import (top-level `secret.value()`, a missing param) fails `emulators:exec` before it can fail a deploy.

## Does not exist / common mistakes

- `FirebaseExtended/action-hosting-deploy` for functions — Hosting only.
- `w9jds/firebase-action` with a `FIREBASE_TOKEN` — works but long-lived token; prefer WIF + `npx firebase-tools`.
- `firebase deploy --token "$FIREBASE_TOKEN"` — deprecated auth path.
- `permissions: id-token: write` missing → `google-github-actions/auth` fails with "unable to get ACTIONS_ID_TOKEN_REQUEST_TOKEN".
- `environment: production` without required reviewers configured in repo settings — the gate is decorative.
- `npm install` instead of `npm ci` — lockfile drift between the tested and deployed tree.
- Running the deploy job on `pull_request` — PRs from forks cannot mint the OIDC token, and you do not want deploy-on-PR anyway.
- Installing `firebase-tools` unpinned (`npm i -g firebase-tools`) — a CLI major bump changes deploy behaviour on a random Tuesday.

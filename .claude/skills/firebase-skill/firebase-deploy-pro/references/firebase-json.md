# firebase.json

`firebase.json` sits at the repo's `Server/` root next to `.firebaserc`, `firestore.rules`, `firestore.indexes.json`, `storage.rules`, and the `functions/` source dir. It tells the CLI what to deploy, how to build it, and how to emulate it. Annotated reference below; JSON has no comments, so the comments are stripped in the real file.

## Annotated file

```jsonc
{
  // ---- Cloud Functions -------------------------------------------------
  // An ARRAY: one entry per codebase. A single object is accepted but the
  // array form is what you want once a second codebase appears.
  "functions": [
    {
      "source": "functions",                 // dir with package.json; $RESOURCE_DIR in predeploy
      "codebase": "api",                     // logical group; deploy with --only functions:api
      "runtime": "nodejs22",                 // must agree with functions/package.json "engines"
      "predeploy": [
        "npm --prefix \"$RESOURCE_DIR\" run lint",
        "npm --prefix \"$RESOURCE_DIR\" run build"
      ],
      // Files NOT uploaded. node_modules is re-installed by Cloud Build from
      // package-lock.json; tests, logs and local env files must never ship.
      "ignore": [
        "node_modules",
        ".git",
        "firebase-debug.log",
        "firebase-debug.*.log",
        "*.local",                            // .env.local, .secret.local
        "test",
        "coverage",
        "src"                                 // only lib/ (compiled) is needed at runtime
      ]
    },
    {
      // Second codebase: heavy AI workers with their own deps and deploy cadence.
      "source": "functions-ai",
      "codebase": "ai",
      "runtime": "nodejs22",
      "predeploy": ["npm --prefix \"$RESOURCE_DIR\" run build"],
      "ignore": ["node_modules", ".git", "*.local", "test", "src"]
    }
  ],

  // ---- Firestore -------------------------------------------------------
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  },
  // Multiple databases (CLI 13.x+): use an array with a "database" key per entry.
  // "firestore": [
  //   { "database": "(default)", "rules": "firestore.rules", "indexes": "firestore.indexes.json" },
  //   { "database": "analytics", "rules": "firestore.analytics.rules", "indexes": "firestore.analytics.indexes.json" }
  // ],

  // ---- Storage ---------------------------------------------------------
  "storage": { "rules": "storage.rules" },
  // Per-bucket rules use deploy targets:
  // "storage": [{ "target": "uploads", "rules": "storage.uploads.rules" }]
  // + firebase target:apply storage uploads snaptool-prod-uploads -P prod

  // ---- Emulators (see firebase-testing-pro → emulator-suite.md) --------
  "emulators": {
    "functions": { "port": 5001 },
    "firestore": { "port": 8080 },
    "auth":      { "port": 9099 },
    "storage":   { "port": 9199 },
    "tasks":     { "port": 9499 },
    "eventarc":  { "port": 9299 },
    "ui":        { "enabled": true, "port": 4000 },
    "singleProjectMode": true
  }
}
```

## Functions entry — field by field

| Field | Notes |
|---|---|
| `source` | Directory containing `package.json`. The CLI zips it (minus `ignore`) and Cloud Build runs `npm ci` there. |
| `codebase` | Name for `--only functions:<codebase>`. Each codebase deploys independently; a function name must be unique across codebases in the same project. Default is `"default"`. |
| `runtime` | `nodejs22`. Overrides `engines.node`; keep both equal so local `node` matches. `nodejs20` still deploys; `nodejs18` is past end-of-support — bump. |
| `predeploy` | Shell commands run before upload; failure aborts the deploy. `$RESOURCE_DIR` expands to `source`. Lint + build here means CI cannot deploy an unbuilt tree. `postdeploy` also exists (e.g. notify Slack). |
| `ignore` | Glob patterns relative to `source`. The CLI already ignores `node_modules`, `.git`, `firebase-debug*.log` by default when `ignore` is absent — once you set `ignore`, list them again. |

`package.json` in `source` must have `"main": "lib/index.js"`, `"engines": { "node": "22" }`, and every runtime dependency in `dependencies` — the build service installs production dependencies only, so a runtime import from `devDependencies` fails at cold start with `Cannot find module`, not at deploy.

### When to split codebases

- Different dependency weight: the `api` codebase stays small for cold starts; `ai` pulls in `@google/genai`, `sharp`, `@google-cloud/vision`.
- Different deploy cadence or owners.
- More than ~60 functions in one codebase: deploys hit Cloud Build / API quotas; the CLI retries but it is slow. Split.
- Shared code between codebases goes in a local package (`packages/shared`, referenced via `"file:../packages/shared"`) — the CLI uploads `file:` dependencies (verify against firebase docs for the version pinned); or duplicate deliberately.

## Firestore rules and indexes

- `firestore.rules` and `firestore.indexes.json` are deployed with `firebase deploy --only firestore` (both) or `firestore:rules` / `firestore:indexes` individually.
- Indexes: the CLI **creates** missing indexes and **deletes** indexes present in the project but absent from the file (after a confirmation prompt; `--force` skips it). Pull the current set with `firebase firestore:indexes > firestore.indexes.json` before the first deploy so nothing is dropped.
- Index builds take minutes; a query that needs one fails with `FAILED_PRECONDITION` until it is `READY`. Deploy indexes before the function or client that runs the query.
- Rules compile errors fail the deploy before anything else is touched — put `--only firestore:rules` first in the deploy script so a rules typo aborts early.

## Storage

- `storage.rules` deploys with `--only storage`. Rules apply to the default bucket unless `target` mapping says otherwise.
- The default bucket's region is the project's default GCP resource location, chosen at project creation and immutable — set it to `asia-southeast1` when creating each project.

## Emulators

Covered in `firebase-testing-pro` → `references/emulator-suite.md`. Keep the block in this file so `emulators:exec` and the iOS `useEmulator` ports have a single source of truth.

## Files next to firebase.json

```
Server/
  .firebaserc
  firebase.json
  firestore.rules
  firestore.indexes.json
  storage.rules
  seed/                       # emulator export (test data only)
  functions/
    package.json
    package-lock.json
    tsconfig.json
    .env
    .env.snaptool-staging
    .env.snaptool-prod
    .env.local                # git-ignored
    .secret.local             # git-ignored
    src/index.ts
    lib/                      # git-ignored build output
    test/
  .gitignore
```

```
# Server/.gitignore
node_modules/
lib/
*.local
*-debug.log
.firebase/
coverage/
```

## Hosting, Remote Config, Extensions

Not part of this backend, but if they appear: `"hosting"` (deploy with `--only hosting`, `FirebaseExtended/action-hosting-deploy` is for this only), `"remoteconfig": { "template": "remoteconfig.template.json" }` (server-side flags — see `rollback-and-incidents.md`), `"extensions": { "delete-user-data": "firebase/delete-user-data@0.1.x" }` with params in `extensions/*.env` — the **Delete User Data** extension is the standard answer for account-deletion cleanup.

## Does not exist / common mistakes

- `"functions": { "region": "asia-southeast1" }` — region is a per-function option (`setGlobalOptions` / function options), not a `firebase.json` key.
- `"functions": { "env": {...} }` or `"environment"` — params come from `.env*` files; there is no env block here.
- `"runtime": "nodejs22"` in `firebase.json` and `"engines": { "node": "20" }` in `package.json` — the CLI uses `firebase.json` but local tooling uses `engines`; keep them equal.
- `"predeploy": "npm run build"` without `--prefix "$RESOURCE_DIR"` — runs in `Server/`, where there is no `package.json`.
- `"ignore"` that omits `node_modules` — uploads hundreds of MB and the deploy times out.
- `"source": "functions/lib"` — the source must contain `package.json`; point at `functions` and set `main` to `lib/index.js`.
- Two codebases exporting a function with the same name — deploy of the second deletes/overwrites the first's; names are project-wide.
- `"firestore": { "rules": ... }` without `indexes` — deploying `--only firestore` then deletes nothing but also creates nothing; the query index you added in the console is not tracked. Always keep `firestore.indexes.json` in the repo.

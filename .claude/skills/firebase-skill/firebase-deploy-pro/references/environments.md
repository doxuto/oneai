# Environments

Three Firebase projects, one per environment. Everything that differs between them lives in `.firebaserc`, `.env.<projectId>`, Secret Manager, and one `GoogleService-Info.plist` per Xcode configuration. Code never knows which environment it is in.

## Projects

| Alias | Project id | Who uses it | Data | Budget |
|---|---|---|---|---|
| `default` (dev) | `snaptool-dev` | developers, Xcode Debug builds, the emulator is preferred | throwaway | tiny, alert at $10 |
| `staging` | `snaptool-staging` | CI on `main`, TestFlight internal builds, QA | anonymised / synthetic | small |
| `prod` | `snaptool-prod` | App Store users | real | real, alert at 50/90/100 % |

Rules:

- Never one project for dev and prod. Not "for now", not "just Auth".
- Same region for all three (`asia-southeast1` for Firestore, Functions, and the default Storage bucket) so region-dependent bugs appear in dev.
- Same Firebase products enabled, same Auth providers, same App Check providers (with debug tokens registered only in dev/staging), same Firestore TTL policies and indexes. Drift between staging and prod is the second most common source of "works in staging".
- Prod project has a separate GCP billing budget, the Blaze plan, and no developer with `Owner` day to day — deploys go through CI.
- APNs auth key (`.p8`) uploaded to **each** project's Cloud Messaging settings; Sign in with Apple configured for each bundle id; the Apple Services ID / return URL differs per project.

## `.firebaserc`

```json
{
  "projects": {
    "default": "snaptool-dev",
    "staging": "snaptool-staging",
    "prod": "snaptool-prod"
  }
}
```

- `firebase use staging` switches the local default; it writes to `.firebaserc`'s `activeProject` in your user config, not the repo. Scripts and CI ignore it and pass `-P` every time.
- `firebase use --add` creates an alias interactively; commit the result.
- `firebase projects:list` to confirm the ids; `firebase use` with no args prints the active alias.
- Do not add the `demo-snaptool` emulator id here — it is passed with `--project demo-snaptool` on `emulators:*` commands only.

## Params — `.env.<projectId>` files

`firebase-functions/params` reads, in order of precedence (highest first): `.env.local` (emulator only, git-ignored), `.env.<projectId>` or `.env.<alias>`, `.env`. Files live in the functions source dir (`functions/`). Values are strings; `defineInt` / `defineBoolean` / `defineList` parse them.

```
# functions/.env                    committed — defaults for every environment
REGION=asia-southeast1
OCR_DAILY_QUOTA=20
PUSH_ENABLED=true
GEMINI_MODEL=gemini-2.5-flash

# functions/.env.snaptool-staging   committed
OCR_DAILY_QUOTA=50
SENTRY_ENV=staging

# functions/.env.snaptool-prod      committed
OCR_DAILY_QUOTA=100
SENTRY_ENV=production
PUSH_ENABLED=true

# functions/.env.local              git-ignored — emulator overrides
PUSH_ENABLED=false
```

```ts
import { defineBoolean, defineInt, defineList, defineString } from "firebase-functions/params";

export const REGION = defineString("REGION", { default: "asia-southeast1" });
export const OCR_DAILY_QUOTA = defineInt("OCR_DAILY_QUOTA", { default: 20 });
export const PUSH_ENABLED = defineBoolean("PUSH_ENABLED", { default: true });
export const GEMINI_MODEL = defineString("GEMINI_MODEL", { default: "gemini-2.5-flash" });
export const ALLOWED_ORIGINS = defineList("ALLOWED_ORIGINS", { default: [] });
```

- `.value()` only inside handlers. At module scope during deploy analysis it throws.
- Keys must not start with `FIREBASE_`, `GCLOUD_`, `X_GOOGLE_`, `EXT_` (reserved; deploy fails).
- Missing key with no `default`: the CLI prompts interactively at deploy time — which hangs `--non-interactive`. Give every param a default or a value in every `.env.<projectId>`.
- Params can also be used in function options (`maxInstances: MAX_INSTANCES` with `defineInt`) so a prod/staging difference in scaling is config, not code.
- `functions.config()` and `firebase functions:config:set` are the deprecated v1 mechanism (removed for new deployments from March 2026). Migrate with `firebase functions:config:export`, which writes `.env.<projectId>` files.

## Secrets — Secret Manager, per project

```bash
firebase functions:secrets:set GEMINI_API_KEY -P staging     # prompts for the value; creates a new version
firebase functions:secrets:set GEMINI_API_KEY -P prod
firebase functions:secrets:access GEMINI_API_KEY -P prod     # print (audit-logged)
firebase functions:secrets:destroy GEMINI_API_KEY@1 -P prod  # destroy an old version
firebase functions:secrets:prune -P prod                     # destroy versions no deployed function references
```

```ts
import { defineSecret } from "firebase-functions/params";
const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
export const extractText = onCall({ secrets: [GEMINI_API_KEY] }, async (req) => {
  const key = GEMINI_API_KEY.value();   // inside the handler only
});
```

- One secret name, one value per project. The same code deployed with `-P staging` picks up staging's value.
- Secrets never go in `.env*` files, never in GitHub secrets for the deploy job (the deploy needs *access* to Secret Manager, not the values), never in logs.
- Emulator: `functions/.secret.local` (git-ignored) with `GEMINI_API_KEY=...`. For `demo-` projects nothing else is consulted.
- Secret Manager is billed per active secret version per month plus access operations; `prune` old versions after rotation.
- Rotation: `secrets:set` (new version) → `firebase deploy --only functions` (functions bind to the latest version at deploy) → `secrets:prune`.

## Environment-specific code — don't

```ts
// Wrong
if (process.env.GCLOUD_PROJECT === "snaptool-prod") sendRealPush();

// Right
if (PUSH_ENABLED.value()) await deps.messaging.send(msg);
```

`process.env.GCLOUD_PROJECT` is fine for *labels* (log fields, Sentry environment) but never for behaviour.

## iOS side — one plist per configuration

Three Xcode build configurations, three bundle ids, three plists. The app never chooses a project at runtime.

| Configuration | Bundle id | Firebase project | Plist path |
|---|---|---|---|
| Debug | `com.doxuto.snaptool.dev` | `snaptool-dev` | `Firebase/Dev/GoogleService-Info.plist` |
| Staging | `com.doxuto.snaptool.staging` | `snaptool-staging` | `Firebase/Staging/GoogleService-Info.plist` |
| Release | `com.doxuto.snaptool` | `snaptool-prod` | `Firebase/Prod/GoogleService-Info.plist` |

Each iOS app is registered in its own Firebase project with its own bundle id; App Check (App Attest / DeviceCheck) and APNs are configured per project.

Copy the right plist with a run-script build phase (before "Copy Bundle Resources"; input files listed so Xcode tracks them):

```bash
# Build Phase: "Select GoogleService-Info.plist"
set -euo pipefail
case "${CONFIGURATION}" in
  Debug)   SRC="${SRCROOT}/Firebase/Dev/GoogleService-Info.plist" ;;
  Staging) SRC="${SRCROOT}/Firebase/Staging/GoogleService-Info.plist" ;;
  Release) SRC="${SRCROOT}/Firebase/Prod/GoogleService-Info.plist" ;;
  *) echo "error: unknown configuration ${CONFIGURATION}"; exit 1 ;;
esac
cp "${SRC}" "${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/GoogleService-Info.plist"
```

Do not add any `GoogleService-Info.plist` to "Copy Bundle Resources" (it would be overwritten unpredictably). `FirebaseApp.configure()` then reads the one the script copied.

Alternative without a script — explicit options:

```swift
import FirebaseCore

enum FirebaseEnvironment {
  static func configure() {
    #if DEBUG
    let name = "GoogleService-Info-Dev"
    #elseif STAGING
    let name = "GoogleService-Info-Staging"
    #else
    let name = "GoogleService-Info-Prod"
    #endif
    guard let path = Bundle.main.path(forResource: name, ofType: "plist"),
          let options = FirebaseOptions(contentsOfFile: path) else {
      fatalError("Missing \(name).plist")
    }
    FirebaseApp.configure(options: options)
  }
}
```

(`STAGING` is a custom `Active Compilation Condition` on the Staging configuration.) This ships all three plists in the bundle; plists are not secrets (API keys are restricted by bundle id and App Check), but prefer the script approach so a prod build cannot contain a dev project id.

Also per configuration on iOS: `PRODUCT_BUNDLE_IDENTIFIER`, display name (`SnapTool Dev`), an app icon badge, the App Check provider (debug in Debug only — see `firebase-testing-pro` → `references/ios-against-emulator.md`), and the `Functions.functions(region:)` string, which is the same in all environments because all three projects live in `asia-southeast1`.

## Onboarding a new environment (checklist)

1. Create the project, same region, Blaze plan, budget alert.
2. Enable the same APIs (Cloud Functions, Cloud Run, Cloud Build, Artifact Registry, Secret Manager, Cloud Scheduler, Cloud Tasks, Eventarc) — the first `firebase deploy` enables most, `--non-interactive` fails on the prompt, so do the first deploy by hand or pre-enable with `gcloud services enable`.
3. Register the iOS app with the environment's bundle id; download the plist into `Firebase/<Env>/`.
4. Upload the APNs key; configure Sign in with Apple; register App Check providers.
5. Add the alias to `.firebaserc`; create `functions/.env.<projectId>`.
6. `firebase functions:secrets:set` every secret in `src/` (`grep -o 'defineSecret("[A-Z_]*")' src/**/*.ts`).
7. Create the WIF binding and deployer service account (see `github-actions.md`).
8. `firebase deploy -P <alias> --only firestore:rules,firestore:indexes,storage`, then `--only functions`.
9. Set the three alerting policies and the uptime check (see `monitoring.md`).

## Does not exist / common mistakes

- `.firebaserc` with `"targets"` used to point functions at a project — targets are for Hosting/Storage/Database resources, not environments.
- `firebase use prod` committed in a shell script — the next developer's `firebase deploy` goes to prod. Always `-P`.
- `.env.production` — the file name is the project id (or alias) — `.env.snaptool-prod` / `.env.prod`.
- `process.env.NODE_ENV` — not set by the Functions runtime in any meaningful way; do not branch on it.
- Reading a secret with `process.env.GEMINI_API_KEY` — works only for functions that declared `secrets: [...]`; use `defineSecret(...).value()` so the declaration and the read stay together.
- One `GoogleService-Info.plist` with the prod project and `useEmulator` in Debug "so we don't need a dev project" — dev builds then write real data whenever someone forgets the emulator.

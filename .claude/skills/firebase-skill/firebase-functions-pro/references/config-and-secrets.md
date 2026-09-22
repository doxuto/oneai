# Configuration and secrets

Two mechanisms, both from `firebase-functions/params`:

- **Params** (`defineString`, `defineInt`, `defineBoolean`, `defineList`) — non-secret configuration read from `.env` files at deploy time. Values are baked into the deployed function as environment variables.
- **Secrets** (`defineSecret`) — stored in Google Secret Manager, mounted into the function at runtime, never written to `.env`, never visible in the console function config.

`functions.config()` and `firebase functions:config:set` are the v1 runtime-config system. Deprecated, and removed for new deployments from March 2026. Never use them; if you find them in a codebase, migrate (see the end of this file).

## Params

```ts
// src/lib/params.ts — one file declares everything
import { defineString, defineInt, defineBoolean, defineSecret } from "firebase-functions/params";

export const SENTRY_DSN = defineString("SENTRY_DSN");
export const DAILY_AI_QUOTA = defineInt("DAILY_AI_QUOTA", { default: 50 });
export const AI_MODEL = defineString("AI_MODEL", { default: "gemini-2.5-flash" });
export const FEATURE_OCR = defineBoolean("FEATURE_OCR", { default: false });
export const MIN_APP_VERSION = defineString("MIN_APP_VERSION", { default: "1.0.0" });

export const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
export const REVENUECAT_WEBHOOK_TOKEN = defineSecret("REVENUECAT_WEBHOOK_TOKEN");
```

Read inside a handler:

```ts
export const chat = onCall({ secrets: [GEMINI_API_KEY] }, async (request) => {
  const quota = DAILY_AI_QUOTA.value();      // number
  const model = AI_MODEL.value();            // string
  const key = GEMINI_API_KEY.value();        // string, populated only because secrets: [] lists it
  ...
});
```

`.value()` at module top level returns an empty string or default during the CLI's deploy-time analysis, and the CLI warns. It also freezes the value into the module for the instance's lifetime, which breaks the emulator's `.env.local` overrides. Always read inside the handler or inside a lazily-called getter.

### Param options

```ts
defineString("NAME", {
  default: "x",
  description: "Shown by the CLI when prompting",
  input: { select: { options: [{ value: "a" }, { value: "b" }] } },   // CLI prompt shape
});
defineInt("N", { default: 10 });
defineBoolean("FLAG", { default: false });
defineList("ALLOWED_ORIGINS", { default: ["https://app.example.com"] });   // comma-separated in .env
```

If a param has no default and no `.env` value, `firebase deploy` prompts interactively and writes the answer to `.env.<projectId>`. In CI use `--non-interactive` and make sure every param is set, or the deploy fails.

### Params in options (deploy-time, not runtime)

Params can drive runtime options because the CLI resolves them at deploy:

```ts
const MIN_INSTANCES = defineInt("CHAT_MIN_INSTANCES", { default: 0 });

export const chat = onCall(
  { minInstances: MIN_INSTANCES, memory: "512MiB" },   // resolved per project at deploy
  async (request) => { ... },
);
```

Use this for per-environment `minInstances` (0 in dev, 1 in prod) without branching in code. Built-in params `projectID`, `databaseURL`, `storageBucket`, `gcloudProject` are exported from `firebase-functions/params` too.

## `.env` files

Located in `functions/`. Loaded in this order, later wins:

1. `.env` — shared defaults, committed.
2. `.env.<projectId>` — e.g. `.env.snaptool-prod`, committed.
3. `.env.local` — developer overrides, only loaded by the emulator, gitignored.

```
# functions/.env
AI_MODEL=gemini-2.5-flash
DAILY_AI_QUOTA=50
FEATURE_OCR=false
MIN_APP_VERSION=1.0.0
```

```
# functions/.env.snaptool-prod
DAILY_AI_QUOTA=200
FEATURE_OCR=true
```

Rules:

- Never put a secret in any `.env` file, including `.env.local`. The CLI refuses keys that collide with a `defineSecret` name, but a plain `defineString("API_KEY")` would happily ship it into the function's environment and the console.
- Reserved prefixes: keys starting with `X_GOOGLE_`, `FIREBASE_`, `EXT_`, `GCLOUD_`, and a handful of platform names (`PORT`, `K_SERVICE`, `K_REVISION`, `K_CONFIGURATION`, `FUNCTION_TARGET`, `FUNCTION_SIGNATURE_TYPE`) are rejected.
- `.env` values are strings. `defineInt`/`defineBoolean` parse them; `process.env.X` does not.

## Secrets

```bash
firebase functions:secrets:set GEMINI_API_KEY                 # prompts for the value; creates a new version
firebase functions:secrets:set GEMINI_API_KEY -P snaptool-prod
firebase functions:secrets:access GEMINI_API_KEY              # print current value (careful in CI logs)
firebase functions:secrets:destroy GEMINI_API_KEY@1           # remove a specific version
firebase functions:secrets:prune                              # remove versions no deployed function uses
```

- Declare with `defineSecret("NAME")` and list it on every function that reads it: `secrets: [GEMINI_API_KEY]`. A function that omits the declaration sees an empty string at runtime — no error.
- The function binds to the latest secret version at deploy. After `secrets:set`, redeploy the functions that use it; running instances keep the old value.
- Secrets can also be passed as strings — `secrets: ["GEMINI_API_KEY"]` — but the `defineSecret` object gives a typed `.value()` and lets the CLI verify existence before deploy. Use the object form.
- Secret Manager charges per active version and per access; the functions runtime fetches once per instance start, so cost is negligible. Do not "optimise" by caching secrets in Firestore.
- Cross-project secrets (a shared prod key used by a staging project) are not supported by the CLI. Set the secret in each project.

### Reading secrets safely

```ts
// module-level memoised client — created on first call, reused for the instance's lifetime
let genai: GoogleGenAI | undefined;
function getGenAI(): GoogleGenAI {
  genai ??= new GoogleGenAI({ apiKey: GEMINI_API_KEY.value() });
  return genai;
}

export const chat = onCall({ secrets: [GEMINI_API_KEY] }, async (request) => {
  const ai = getGenAI();   // .value() runs inside the request, once per instance
  ...
});
```

This pattern is correct because the getter runs inside a handler on a function that declared the secret. The same getter called from a function without `secrets: [GEMINI_API_KEY]` builds a client with an empty key — put the getter next to the functions that use it, not in a shared file every function imports.

## Emulator

- The emulator loads `.env`, `.env.<projectId>`, and `.env.local`.
- Secrets: the emulator reads them from `.secret.local` (gitignored) in `functions/`, one `KEY=value` per line. It does not call Secret Manager unless you are logged in and the secret exists; put dev keys in `.secret.local`.
- `firebase emulators:exec` and `emulators:start` warn once about any `defineSecret` not present in `.secret.local`.

## Environment detection

```ts
const isEmulator = process.env.FUNCTIONS_EMULATOR === "true";
const projectId = process.env.GCLOUD_PROJECT;   // set in both emulator and production
```

Use `projectId` for per-environment switches when a param would be overkill (e.g. picking the App Store sandbox verifier). Prefer a param when the value is data, not identity.

## Migrating from `functions.config()`

1. List current values: `firebase functions:config:get > config.json`.
2. For each non-secret key, add a line to `.env` / `.env.<projectId>` with an UPPER_SNAKE name and a `defineString`/`defineInt` in `params.ts`.
3. For each secret, `firebase functions:secrets:set NAME` and `defineSecret`.
4. Replace every `functions.config().x.y` with `X_Y.value()` inside handlers, and add `secrets: []` to the functions that read secrets.
5. Delete `.runtimeconfig.json` if present. Deploy. Then `firebase functions:config:unset` the old keys once no v1 function reads them.

The CLI's `firebase functions:config:export` can generate `.env` files from existing config as a starting point; review the output for secrets before committing.

## Does not exist / common mistakes

- `functions.config()` — deprecated and removed. Params + secrets.
- `process.env.GEMINI_API_KEY` for a `defineSecret` — works at runtime (the secret is mounted as an env var) but bypasses the deploy-time check and typing, and breaks in the emulator without `.secret.local`. Use `.value()`.
- `defineSecret(...).value()` at module top level — empty during deploy analysis; the CLI warns and the value never refreshes.
- `secrets: []` omitted on a function that calls `.value()` — silent empty string.
- Setting a secret and not redeploying — instances keep the old version.
- `dotenv` package in functions — unnecessary; the runtime loads `.env` files itself and `dotenv` can override deployed params.
- `defineString("KEY").value()` used in `setGlobalOptions` — `setGlobalOptions` runs at module load; use a literal there or pass the param object to per-function options instead.

# Project layout

The layout is per-function: one exported function per file, grouped by domain, re-exported from a single barrel. Deploys, logs, IAM, and runtime options are all per-function in 2nd gen, and the file tree should make that visible.

## Repository shape

```
Server/
  firebase.json
  .firebaserc
  firestore.rules
  firestore.indexes.json
  storage.rules
  functions/
    package.json
    tsconfig.json
    .env                      # shared non-secret params (committed)
    .env.snaptool-dev         # per-project overrides (committed)
    .env.snaptool-prod
    .env.local                # local-only overrides (gitignored)
    src/
      index.ts                # setGlobalOptions + barrel re-exports, nothing else
      lib/
        admin.ts              # lazy admin init, exports db/auth/messaging
        errors.ts             # mapError helper
        validate.ts           # parse<T>(schema, data) helper
      notes/
        createNote.ts
        deleteNote.ts
        onNoteWritten.ts      # Firestore trigger
      ai/
        chat.ts
        summarize.ts
      billing/
        revenueCatWebhook.ts  # onRequest
      users/
        onUserDeleted.ts      # v1 auth trigger, explicitly marked
    test/
      createNote.test.ts
```

## firebase.json

```json
{
  "functions": [
    {
      "source": "functions",
      "codebase": "api",
      "runtime": "nodejs22",
      "predeploy": ["npm --prefix \"$RESOURCE_DIR\" run build"]
    }
  ],
  "firestore": { "rules": "firestore.rules", "indexes": "firestore.indexes.json" },
  "storage": { "rules": "storage.rules" },
  "emulators": {
    "functions": { "port": 5001 },
    "firestore": { "port": 8080 },
    "auth": { "port": 9099 },
    "storage": { "port": 9199 },
    "ui": { "enabled": true }
  }
}
```

Split into multiple codebases (`"codebase": "api"`, `"codebase": "jobs"`) only when deploy times or dependency sets diverge. Each codebase has its own `functions/`-style folder and `package.json`.

## package.json

```json
{
  "name": "functions",
  "type": "module",
  "engines": { "node": "22" },
  "main": "lib/index.js",
  "scripts": {
    "build": "tsc",
    "build:watch": "tsc --watch",
    "serve": "npm run build && firebase emulators:start --only functions,firestore,auth",
    "test": "firebase emulators:exec --only firestore,auth \"vitest run\"",
    "deploy": "firebase deploy --only functions",
    "logs": "firebase functions:log"
  },
  "dependencies": {
    "firebase-admin": "^13.0.0",
    "firebase-functions": "^6.2.0",
    "zod": "^3.23.0"
  },
  "devDependencies": {
    "firebase-functions-test": "^3.3.0",
    "typescript": "^5.5.0",
    "vitest": "^2.0.0"
  }
}
```

- `"engines": { "node": "22" }` must match `"runtime": "nodejs22"` in `firebase.json`. Mismatch causes a deploy warning or a silent fallback to the older runtime.
- `"type": "module"` with NodeNext requires `.js` extensions on relative imports in TS source (`from "./lib/admin.js"`). If the project is CommonJS instead, drop `"type": "module"` and use `"module": "CommonJS"`; do not mix.
- `"main"` points at the compiled output. The CLI loads this file to discover exports at deploy time — anything that runs at import must be cheap and must not require secrets.

## tsconfig.json

```json
{
  "compilerOptions": {
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "target": "ES2022",
    "lib": ["ES2022"],
    "outDir": "lib",
    "rootDir": "src",
    "strict": true,
    "noImplicitReturns": true,
    "noUnusedLocals": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "sourceMap": true
  },
  "include": ["src"],
  "exclude": ["test"]
}
```

`sourceMap: true` gives readable stack traces in Cloud Logging. Exclude tests from the build so they are not deployed.

## src/index.ts — the barrel

```ts
import { setGlobalOptions } from "firebase-functions/v2";

// Global defaults. Per-function options override these.
setGlobalOptions({
  region: "asia-southeast1",
  maxInstances: 10,
});

// Domain barrels. Every export here becomes a deployed function with this name.
export { createNote } from "./notes/createNote.js";
export { deleteNote } from "./notes/deleteNote.js";
export { onNoteWritten } from "./notes/onNoteWritten.js";
export { chat } from "./ai/chat.js";
export { summarize } from "./ai/summarize.js";
export { revenueCatWebhook } from "./billing/revenueCatWebhook.js";
export { onUserDeleted } from "./users/onUserDeleted.js";
```

Rules:

- `setGlobalOptions` must run before any function module is evaluated. Put it at the top of `index.ts`; ES module imports are hoisted, so it must be the only statement in this file besides re-exports, and each function file must not import `index.ts`.
- Do not `export *`. Explicit names make the deployed function list greppable and stop an accidental helper export from becoming a function.
- The export name is the deployed name and what the iOS client passes to `httpsCallable("createNote")`. Renaming an export deletes and recreates the function (see `v1-to-v2-migration.md`).
- Grouping exports in an object (`export const notes = { createNote }`) deploys as `notes-createNote`. Avoid it; it makes the client name non-obvious and complicates `--only` targets.

## src/lib/admin.ts — lazy admin init

```ts
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import { getMessaging } from "firebase-admin/messaging";
import { getStorage } from "firebase-admin/storage";

if (getApps().length === 0) initializeApp();

export const db = getFirestore();
db.settings({ ignoreUndefinedProperties: true }); // once, before first read/write

export const auth = getAuth();
export const messaging = getMessaging();
export const storage = getStorage();
```

- One file initialises admin; every function imports from it. `getApps().length === 0` guards against double init in tests and in the emulator's hot reload.
- `db.settings()` throws if called after the first operation, so it lives next to `getFirestore()` and nowhere else.
- Modular imports only (`firebase-admin/app`, not `import * as admin from "firebase-admin"`). The namespaced import still works in 13.x but pulls the whole SDK into the cold path.

## One function per file

```ts
// src/notes/deleteNote.ts
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { z } from "zod";
import { db } from "../lib/admin.js";
import { parse } from "../lib/validate.js";

const Input = z.object({ noteId: z.string().min(1) });

export const deleteNote = onCall({ enforceAppCheck: true }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required");
  const { noteId } = parse(Input, request.data);
  await db.recursiveDelete(db.doc(`users/${request.auth.uid}/notes/${noteId}`));
  return { ok: true };
});
```

- File name equals export name (`deleteNote.ts` → `export const deleteNote`). Triggers use `on<Thing><Event>.ts` (`onNoteWritten.ts`, `onUploadFinalized.ts`).
- Shared helpers go in `src/lib/`. Domain-private helpers live next to their functions in a `_shared.ts` that exports no functions.
- A file must never export two functions. `firebase deploy --only functions:deleteNote` targets by export name, and per-function `secrets`/`memory` are easier to audit when the file and the function are the same unit.

## Naming

- Callables: camelCase verb + noun, from the client's point of view: `createNote`, `redeemCode`, `chat`. No `Fn`/`Function` suffix, no `api` prefix.
- Triggers: `on` + subject + event: `onNoteCreated`, `onUserDeleted`, `onScanUploaded`.
- Scheduled: describe the job: `pruneStaleTokens`, `nightlyDigest`.
- Task workers: `process` + subject: `processScan`. The queue name equals the function name when enqueuing with `getFunctions().taskQueue("processScan")`.
- Versioned callables: suffix `V2` (`createNoteV2`) — never change the shape of an existing callable in place while a shipped iOS build calls it. See `firebase-ios-contract` → `references/versioning.md`.

## Environments

`.firebaserc`:

```json
{ "projects": { "default": "snaptool-dev", "staging": "snaptool-staging", "prod": "snaptool-prod" } }
```

`firebase use prod` or `firebase deploy -P prod --only functions`. Params come from `.env.<projectId>`; secrets are set per project with `firebase functions:secrets:set NAME -P prod`. Never share one project between dev and prod.

## Does not exist / common mistakes

- `functions/index.js` with `require("firebase-functions")` and `exports.x = ...` — that is the v1 CommonJS starter. Use TypeScript, ESM, and named exports.
- `initializeApp()` at the top of every function file — double init throws `app/duplicate-app` in tests. One `lib/admin.ts`.
- `import * as functions from "firebase-functions"` then `functions.https.onCall` — that is v1. Import from `firebase-functions/v2/https`.
- Missing `.js` on relative imports with NodeNext — compiles, then fails at runtime with `ERR_MODULE_NOT_FOUND` on deploy.
- Putting `setGlobalOptions` in `lib/admin.ts` or after the re-exports — imports are hoisted, so the options apply to nothing.

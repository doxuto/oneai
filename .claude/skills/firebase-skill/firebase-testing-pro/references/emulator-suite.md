# Emulator Suite

The Local Emulator Suite is the only Firebase you should talk to from a test. Firebase CLI (`firebase-tools`) 13.x or later; the Firestore, Storage, Pub/Sub and UI emulators are Java jars, so a JDK is required (JDK 21 is safe; older CLI releases accepted 11 — verify against firebase docs for the CLI version you pin).

## firebase.json — emulators block

```json
{
  "functions": [{ "source": "functions", "codebase": "api", "runtime": "nodejs22" }],
  "firestore": { "rules": "firestore.rules", "indexes": "firestore.indexes.json" },
  "storage": { "rules": "storage.rules" },
  "emulators": {
    "functions": { "port": 5001, "host": "127.0.0.1" },
    "firestore": { "port": 8080, "host": "127.0.0.1" },
    "auth":      { "port": 9099, "host": "127.0.0.1" },
    "storage":   { "port": 9199, "host": "127.0.0.1" },
    "pubsub":    { "port": 8085 },
    "eventarc":  { "port": 9299 },
    "tasks":     { "port": 9499 },
    "ui":        { "enabled": true, "port": 4000 },
    "hub":       { "port": 4400 },
    "singleProjectMode": true
  }
}
```

- Pin every port. Unpinned ports drift between machines and break the hard-coded `useEmulator(withHost:port:)` calls on iOS.
- `singleProjectMode: true` makes the emulator warn when a test uses a different project id than the CLI was started with — catches a stray `demo-x` vs `demo-snaptool` mismatch.
- `eventarc` is needed for custom-event / Extensions triggers; `pubsub` for `onMessagePublished` triggers; `tasks` for the Cloud Tasks emulator (added to the suite in firebase-tools 13.x — verify against firebase docs if `taskQueue().enqueue()` fails locally).
- Set `"host": "0.0.0.0"` on every emulator you want reachable from a physical iPhone on the same Wi-Fi (see below). Keep `127.0.0.1` in the committed file; override on the command line or in a git-ignored `firebase.json` override is not supported — use a separate `firebase.lan.json` and `--config firebase.lan.json`.

## Starting

```bash
# interactive, keeps running, UI at http://127.0.0.1:4000
firebase emulators:start --only functions,firestore,auth,storage --project demo-snaptool

# with seed data, and write the state back on Ctrl-C
firebase emulators:start --only functions,firestore,auth,storage --project demo-snaptool \
  --import ./seed --export-on-exit

# run a command against a fresh emulator, then shut it down (CI, npm test)
firebase emulators:exec --only functions,firestore,auth,storage --project demo-snaptool \
  --import ./seed "npm run test:integration"

# attach a debugger to functions
firebase emulators:start --only functions --inspect-functions
```

`emulators:exec` exits with the command's exit code, so a failing vitest run fails CI. It also exports `FIRESTORE_EMULATOR_HOST`, `FIREBASE_AUTH_EMULATOR_HOST`, `FIREBASE_STORAGE_EMULATOR_HOST`, `FIREBASE_EMULATOR_HUB`, `GCLOUD_PROJECT` into the child process, so the Admin SDK and `@firebase/rules-unit-testing` auto-discover the emulator without configuration.

Use `--project demo-<name>`. Project ids starting with `demo-` are treated as fake: the emulators never call production APIs, and the Functions emulator does not need credentials. Any other id makes the Functions emulator try real Google APIs for anything without an emulator (FCM, Secret Manager, Gemini) — that is how a "test" sends real pushes.

## Seed data — `--import` / `--export-on-exit`

1. Start the emulator, create the users and documents you want (through the app, the UI at :4000, or a seed script using the Admin SDK).
2. `firebase emulators:export ./seed` (while running) or stop with `--export-on-exit`.
3. Commit `seed/` — it contains `firebase-export-metadata.json`, `firestore_export/`, `auth_export/accounts.json`, `storage_export/`.
4. Every `emulators:exec` and every iOS UI test run starts with `--import ./seed`.

Prefer a seed script over hand-made exports when the shape of the data changes often:

```ts
// scripts/seed.ts — run with: firebase emulators:exec --only firestore,auth --project demo-snaptool --export-on-exit ./seed "npx tsx scripts/seed.ts"
import { initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { getFirestore, Timestamp } from "firebase-admin/firestore";

initializeApp({ projectId: "demo-snaptool" });
const auth = getAuth();
const db = getFirestore();

const alice = await auth.createUser({ uid: "alice", email: "alice@test.dev", password: "password", emailVerified: true });
await auth.setCustomUserClaims(alice.uid, { role: "member" });
await db.doc("users/alice").set({ displayName: "Alice", createdAt: Timestamp.now(), plan: "free" });
await db.doc("users/alice/notes/n1").set({ title: "Seed note", tags: ["seed"], createdAt: Timestamp.now() });
```

Auth emulator passwords in `accounts.json` are stored hashed with a known salt; the exported file is safe to commit for `demo-` projects only.

## Environment inside the Functions emulator

| Variable | Value in emulator | Use |
|---|---|---|
| `FUNCTIONS_EMULATOR` | `"true"` | branch on it only for logging verbosity, never for business logic |
| `GCLOUD_PROJECT` | the `--project` id | |
| `FIRESTORE_EMULATOR_HOST` | `127.0.0.1:8080` | Admin SDK auto-routes |
| `FIREBASE_AUTH_EMULATOR_HOST` | `127.0.0.1:9099` | Admin `getAuth()` auto-routes |
| `FIREBASE_STORAGE_EMULATOR_HOST` | `127.0.0.1:9199` | Admin `getStorage()` auto-routes |

Params (`defineString`) are read from `functions/.env`, `.env.<projectId>`, and `.env.local` (emulator only, git-ignored). Secrets (`defineSecret`) are read from `functions/.secret.local` in the emulator:

```
# functions/.secret.local  (git-ignored)
GEMINI_API_KEY=fake-key-for-local
```

With a `demo-` project the emulator never contacts Secret Manager; a missing `.secret.local` entry yields an empty string, so a handler that calls Gemini at all is a bug in a test — inject a fake (see `unit-testing-functions.md`).

## Emulator UI

`http://127.0.0.1:4000` — Firestore browser (edit docs, run "Clear all data"), Auth users, Storage files, Functions logs, and a **Requests** tab showing rules evaluation per request with the matched `match` block. Use the Firestore "Requests" tab to debug an unexpected `permission-denied` before writing a rules test.

## What the emulator does NOT do

Flag any test that assumes otherwise.

- **Schedules do not fire.** `onSchedule` functions are registered and visible in the UI; trigger them from the UI's Functions tab or, better, call the handler function from a unit test.
- **App Check is not enforced.** `enforceAppCheck: true` is ignored locally; a passing emulator suite says nothing about App Check. Verify in staging with a real device.
- **No FCM emulator.** `getMessaging().send()` in the emulator with a `demo-` project fails (no credentials); with a real project id it sends real pushes. Always inject a fake.
- **No Secret Manager / Gemini / Vision / external HTTP.** Fake them.
- **Auth emulator issues unsigned tokens.** Any code that verifies an ID token with a third-party library (not `getAuth().verifyIdToken`) fails locally.
- **Task queues**: the Tasks emulator dispatches enqueued tasks to the local `onTaskDispatched` function but retry / rate-limit semantics are approximate — test retries at the handler level.
- **Firestore emulator does not enforce composite index requirements.** A query that needs an index in `firestore.indexes.json` succeeds locally and fails in production with `FAILED_PRECONDITION`. Deploy indexes to staging early; keep `firestore.indexes.json` in the same PR as the query.
- **No TTL policies, no PITR, no Firestore quotas.** Emulated `recursiveDelete` and bulk writes are much faster than production.
- **Storage emulator does not generate signed URLs.** `getSignedUrl()` needs a service account; test the path building, not the URL.
- **Regions are ignored.** A trigger declared in the wrong region for its Firestore database deploys fine locally and fails at `firebase deploy`.
- **Blocking functions** (`beforeUserCreated`) are supported by the Auth emulator, but only when the function is registered in `firebase.json`'s functions codebase and the Auth emulator is running in the same session.

## LAN access for a physical device

```bash
# firebase.lan.json: same as firebase.json but every emulator has "host": "0.0.0.0"
firebase emulators:start --config firebase.lan.json --only functions,firestore,auth,storage --project demo-snaptool --import ./seed
ipconfig getifaddr en0   # Mac's Wi-Fi IP, e.g. 192.168.1.20
```

Then launch the app with `FIREBASE_EMULATOR_HOST=192.168.1.20` in the scheme's environment. The iOS Simulator shares the Mac's loopback interface, so `127.0.0.1` works there without any of this. Firewall prompts on macOS must be accepted for `java` and `node`.

## Does not exist / common mistakes

- `firebase emulators:start --project prod-id` with `--import` from a production export: the export format is the same, but the Functions emulator will then call real FCM and Secret Manager. Never use a non-`demo-` id.
- `"emulators": { "functions": { "region": ... } }` — no such key. Region comes from the function options.
- `FIREBASE_FUNCTIONS_EMULATOR_HOST` — not a thing. Clients connect with `useEmulator` / `connectFunctionsEmulator`.
- `firebase emulators:exec` without `--only` starts every emulator configured in `firebase.json`, including Hosting and Pub/Sub; it is slower and needs more ports open, and Hosting prompts if no `public` dir exists.
- Setting `FIRESTORE_EMULATOR_HOST` in `.env` for the functions runtime — the emulator sets it; a hard-coded value in `.env` gets deployed and breaks production.
- Expecting `event.authType` / `event.authId` on `onDocumentCreatedWithAuthContext` to be populated for writes made from the Emulator UI — they arrive as `"unknown"`; write through an authenticated web-SDK client in the test instead.

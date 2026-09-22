# Test strategy for a Firebase Functions backend

This mirrors the `ios-test-strategy` skill: decide *what* to test at *which* layer before writing a single test. The cheapest layer that can catch a bug owns that bug.

## The pyramid

```
                 ┌──────────────────────────┐
                 │ 5. iOS end-to-end         │  XCUITest against emulator + seed. A handful.
                 ├──────────────────────────┤
                 │ 4. Rules tests            │  @firebase/rules-unit-testing. One per allow branch.
                 ├──────────────────────────┤
                 │ 3. Emulator integration   │  web SDK → emulated callable; write doc → trigger fires.
                 ├──────────────────────────┤
                 │ 2. Handler tests          │  handler(uid, data, deps) with Admin SDK on emulator.
                 ├──────────────────────────┤
                 │ 1. Pure logic             │  zod schemas, pricing, quota math, payload builders. No Firebase.
                 └──────────────────────────┘
```

| Layer | Runs with | Speed | Owns |
|---|---|---|---|
| 1. Pure logic | `vitest run` | ms | validation schemas, FCM payload shape, Gemini prompt building, date/quota arithmetic, error mapping |
| 2. Handler | `emulators:exec` (firestore, auth, storage) | 10–100 ms each | Firestore reads/writes, transactions, `create()` idempotency, `HttpsError` codes, custom-claim checks |
| 3. Integration | `emulators:exec` (+ functions) | 0.5–3 s each | callable wire format (auth header, data encoding, error code reaches client), triggers actually fire, task enqueue → worker |
| 4. Rules | `emulators:exec` (firestore, storage) | 10–50 ms each | every `allow` line in `firestore.rules` / `storage.rules` |
| 5. iOS E2E | Xcode + running emulator | 10–60 s each | the one golden path per feature: sign in → call → see result on screen |

Rule of thumb for a feature: 10+ layer-1 tests, 3–6 layer-2, 1–2 layer-3, one rules test per new `match`, at most one iOS E2E.

## What goes where — decision table

| You want to prove… | Layer |
|---|---|
| "title over 200 chars is rejected with `invalid-argument` and `details.fieldErrors.title`" | 1 (schema) or 2 (handler) — prefer 1 |
| "second call with same idempotency key does not create a second doc" | 2 (`ref.create` against emulator) |
| "the caller's `role` claim is checked" | 2 — pass `token: { role: "admin" }` into the handler context |
| "an unauthenticated iOS client gets `.unauthenticated`" | 3 — only the wire proves the code is not swallowed as `internal` |
| "`onNoteCreated` increments `users/{uid}.noteCount`" | 2 for the handler body; one layer-3 test that the trigger is wired to the right path |
| "a user cannot read another user's notes" | 4 |
| "the nightly cleanup deletes expired scans" | 2 — call the schedule handler directly; the emulator never fires schedules |
| "push is sent with `thread-id` = noteId" | 1 (payload builder) + 2 with a fake `messaging` dep |
| "Gemini returns JSON matching the schema" | 1 with a recorded response; never call Gemini in tests |
| "App Check rejects a missing token" | none — the emulator does not enforce App Check; verify in staging manually |
| "the SwiftUI screen shows the created note" | 5 |

## Directory layout

```
functions/
  src/
    index.ts                 # exports only, thin wrappers
    notes/handler.ts         # createNoteHandler(uid, raw, deps)
    notes/schema.ts          # zod
    push/payload.ts          # buildNoteSharedMessage(...) — pure
    push/send.ts             # uses deps.messaging
  test/
    unit/                    # layer 1 + 2
      schema.test.ts
      createNote.test.ts
    integration/             # layer 3
      callables.test.ts
      triggers.test.ts
    rules/                   # layer 4
      firestore.rules.test.ts
      storage.rules.test.ts
    helpers/
      emulator.ts            # clearFirestore(), waitFor(), web SDK app factory
      fakes.ts               # FakeMessaging, fake Gemini
  vitest.config.ts
seed/                        # emulator export used by CI and by the iOS UI tests
firebase.json
```

## npm scripts

```json
{
  "scripts": {
    "build": "tsc",
    "lint": "eslint src test",
    "test": "npm run test:unit && npm run test:integration && npm run test:rules",
    "test:pure": "vitest run --dir test/unit --exclude '**/*.emulator.test.ts'",
    "test:unit": "firebase emulators:exec --only firestore,auth,storage --project demo-snaptool 'vitest run --dir test/unit'",
    "test:integration": "firebase emulators:exec --only functions,firestore,auth,storage --project demo-snaptool --import ../seed 'vitest run --dir test/integration'",
    "test:rules": "firebase emulators:exec --only firestore,storage --project demo-snaptool 'vitest run --dir test/rules'",
    "test:watch": "vitest --dir test/unit"
  }
}
```

`test:watch` assumes `firebase emulators:start --only firestore,auth,storage --project demo-snaptool` is already running in another terminal; the Admin SDK finds it via the env vars you export in `vitest.config.ts` (see `unit-testing-functions.md`).

## The deps object — the one pattern that makes layers 1–2 possible

```ts
export interface Deps {
  db: Firestore;
  auth: Pick<Auth, "getUser" | "setCustomUserClaims">;
  messaging: Pick<Messaging, "send" | "sendEachForMulticast">;
  ai: { extract(input: ExtractInput): Promise<ExtractResult> };
  now: () => Date;
  newId: () => string;
}
```

- Real `db` and `auth` on the emulator. Never fakes — they have emulators.
- Fake `messaging` and `ai` — they have no emulators and cost money.
- `now` / `newId` injected so assertions are deterministic (same rule as `@Dependency(\.date)` in `tca-pro`).
- `index.ts` builds the production `Deps` once at module level and passes it to every handler.

## Layer 5 — iOS end-to-end, kept small

The iOS suite is owned by `xcuitest-pro`. This skill only defines the contract:

- The app launches with `-useFirebaseEmulator` and reads `FIREBASE_EMULATOR_HOST` (see `ios-against-emulator.md`).
- The emulator is started with `--import ./seed` so the test knows which users and documents exist.
- Seed users are created with the Auth emulator and have fixed passwords (`alice@test.dev` / `password`); tests sign in through the real UI or through a test-only deep link.
- One E2E per feature. Anything asserting a validation message, an error code, or a Firestore side effect belongs in layers 1–4.

## Anti-patterns to flag

- A `vitest` file that imports `../../src/index.ts` to test business logic: the import runs `initializeApp()` and registers every function; test the handler.
- `vi.mock("firebase-admin/firestore")` with a hand-written `collection().doc().set()` chain: the mock encodes assumptions instead of testing them.
- Tests that read `process.env.GCLOUD_PROJECT` and fall back to a real project id.
- A single 400-line `integration.test.ts` that seeds everything in `beforeAll` and shares state between `it` blocks — one `clearFirestore()` per test.
- An XCUITest that asserts on a Firestore document via the Admin SDK from Swift — Swift has no Admin SDK; assert on screen, seed via `--import`.
- Snapshot-testing full Firestore documents that contain `serverTimestamp()` — assert on the fields you set, `expect.any(Timestamp)` for the rest.

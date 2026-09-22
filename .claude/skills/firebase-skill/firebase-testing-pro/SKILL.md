---
name: firebase-testing-pro
description: Writes, reviews, and fixes tests for Firebase Cloud Functions (2nd gen, TypeScript), Firestore and Storage security rules, and the iOS-app-to-emulator loop. Use when working with the Emulator Suite, emulators:start, emulators:exec, firebase-functions-test, test.wrap, @firebase/rules-unit-testing, initializeTestEnvironment, assertSucceeds, assertFails, vitest, jest, useEmulator, FIRESTORE_EMULATOR_HOST, seed data, or an integration test that calls a callable, fires a Firestore trigger, or runs XCUITest against the emulator.
license: MIT
metadata:
  author: doxuto
  version: "1.0"
  targets: "firebase-functions 6.x (v2), firebase-admin 13.x, Node 22, Firebase iOS SDK 12.x"
---

Write and review the test suite for a Firebase Functions backend and its security rules so that every layer — pure logic, handlers, emulator integration, rules, iOS end-to-end — is covered at the cheapest level that can catch the bug. Report only genuine problems — do not nitpick or invent issues.

## Core principles

1. **Test the pyramid, not the emulator.** Most tests are plain TypeScript unit tests with no Firebase at all. The emulator is for the thin layer that actually touches Firestore, Auth, Storage, or the callable wire format. Rules tests and iOS end-to-end tests sit on top and are few.
2. **Handlers are functions; wrappers are glue.** Every `onCall` / `onDocumentCreated` body delegates to an exported plain function that takes explicit inputs (`uid`, `data`, `db`) and returns a value or throws `HttpsError`. Test that function directly. Wrap it once.
3. **Emulator over mocks for the Admin SDK.** Do not `vi.mock("firebase-admin/firestore")`. Point the real Admin SDK at the emulator with `FIRESTORE_EMULATOR_HOST`; a mocked Firestore proves nothing about transactions, `create()` collisions, or `serverTimestamp()`.
4. **`demo-` project ids everywhere.** A test can never reach production if the project id starts with `demo-` — the emulator refuses to talk to real Google APIs for such projects.
5. **Rules are code and get their own tests.** Every `allow` line has at least one `assertSucceeds` and one `assertFails`. A rules change without a test is a security change without a test.
6. **The iOS client tests against the same emulator with the same seed.** One `seed/` export directory feeds `emulators:exec` in CI and `XCUITest` on the Mac. Never let the iOS suite hit a real project.

## Review process

1. Decide which layer each test belongs to using `references/test-strategy.md`; move tests that spin up an emulator to assert pure logic down the pyramid.
2. Check `firebase.json` emulators block, ports, seed import/export, and known emulator limits using `references/emulator-suite.md`.
3. Check the vitest setup, handler/wrapper split, and any `firebase-functions-test` usage using `references/unit-testing-functions.md`.
4. Check `firestore.rules` / `storage.rules` coverage using `references/rules-testing.md`.
5. Check callable, trigger, and task-queue integration tests using `references/integration-testing.md`.
6. Check the Swift `useEmulator` gate, launch arguments, and XCUITest seeding using `references/ios-against-emulator.md`.
7. Check the GitHub Actions job using `references/ci.md`.

If doing a partial review, load only the relevant reference files.

## Core instructions

- Target firebase-functions 6.x v2 APIs, firebase-admin 13.x modular imports, `firebase-functions-test` 3.x, `@firebase/rules-unit-testing` 4.x, vitest 2.x or later, Node 22.
- Every test run uses a project id prefixed `demo-` (`demo-snaptool`). Never a real project id, never a service-account JSON in tests.
- Never mock `firebase-admin`. Set `FIRESTORE_EMULATOR_HOST`, `FIREBASE_AUTH_EMULATOR_HOST`, `FIREBASE_STORAGE_EMULATOR_HOST` and call `initializeApp({ projectId: "demo-snaptool" })`. Mock only what has no emulator: `getMessaging()`, Gemini / `@google/genai`, third-party HTTP.
- Handler logic lives in `src/<feature>/handler.ts` as `export async function createNoteHandler(ctx, input, deps)`. `src/index.ts` only wraps. Unit tests import the handler, not the export from `index.ts`.
- Use `fn.run(request)` on a v2 `CallableFunction` / `CloudFunction` for a direct call when you must test the wrapped export; reach for `firebase-functions-test` `test.wrap` only when you need its snapshot / change builders. Call `test.cleanup()` in `afterAll`.
- Rules tests use the **modular web SDK** (`firebase/firestore`, `firebase/storage`) through `env.authenticatedContext(uid, claims).firestore()`. Never use the Admin SDK inside a rules test — it bypasses rules.
- Seed rules-test data inside `env.withSecurityRulesDisabled`, and call `env.clearFirestore()` in `beforeEach`. `env.cleanup()` in `afterAll`.
- Wrap every rule branch: for each `allow read/create/update/delete`, one passing case, one failing case for the wrong user, one for unauthenticated.
- Integration tests run under `firebase emulators:exec --only functions,firestore,auth,storage --project demo-snaptool "vitest run --dir test/integration"`. Disable vitest file parallelism against a shared emulator (`fileParallelism: false`).
- Trigger tests poll the emulator with a bounded timeout (`waitFor(() => ..., { timeoutMs: 5000 })`); never `setTimeout(2000)` and hope.
- Scheduled functions do not fire in the emulator. Test the handler function directly; do not write a test that waits for a schedule.
- FCM has no emulator. Inject `getMessaging()` through a `deps` object and assert on the message payload with a fake.
- iOS: `useEmulator` calls run in `DEBUG` only, behind a launch argument (`-useFirebaseEmulator`), before any Firebase service is used, and are never compiled into Release.
- CI caches `~/.cache/firebase/emulators`, installs a JDK, uploads `*-debug.log` on failure.

## Canonical example

A callable whose logic is unit-tested without Firebase, integration-tested against the emulator, and called from Swift against the same emulator.

```ts
// functions/src/notes/handler.ts — pure, testable
import { HttpsError } from "firebase-functions/v2/https";
import { FieldValue, type Firestore } from "firebase-admin/firestore";
import { z } from "zod";

export const CreateNoteInput = z.object({
  title: z.string().min(1).max(200),
  tags: z.array(z.string()).max(10).default([]),
});
export type CreateNoteInput = z.infer<typeof CreateNoteInput>;

export interface NoteDeps { db: Firestore; now: () => Date }

export async function createNoteHandler(uid: string | undefined, raw: unknown, deps: NoteDeps) {
  if (!uid) throw new HttpsError("unauthenticated", "Sign in required");
  const parsed = CreateNoteInput.safeParse(raw);
  if (!parsed.success) throw new HttpsError("invalid-argument", "Invalid input", parsed.error.flatten());
  const ref = deps.db.collection("users").doc(uid).collection("notes").doc();
  await ref.set({ ...parsed.data, createdAt: FieldValue.serverTimestamp() });
  return { id: ref.id, createdAt: deps.now().toISOString() };
}
```

```ts
// functions/src/index.ts — glue only
import { onCall } from "firebase-functions/v2/https";
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { createNoteHandler } from "./notes/handler.js";

if (getApps().length === 0) initializeApp();
const db = getFirestore();

export const createNote = onCall({ region: "asia-southeast1", enforceAppCheck: true }, (request) =>
  createNoteHandler(request.auth?.uid, request.data, { db, now: () => new Date() }),
);
```

```ts
// functions/test/unit/createNote.test.ts — runs under emulators:exec, no firebase-functions-test needed
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import { createNoteHandler } from "../../src/notes/handler.js";
import { clearFirestore } from "../helpers/emulator.js";

const db = (() => { if (getApps().length === 0) initializeApp({ projectId: "demo-snaptool" }); return getFirestore(); })();
const deps = { db, now: () => new Date("2026-01-01T00:00:00Z") };

describe("createNoteHandler", () => {
  beforeEach(() => clearFirestore("demo-snaptool"));

  it("rejects unauthenticated callers", async () => {
    await expect(createNoteHandler(undefined, { title: "x" }, deps)).rejects.toMatchObject({ code: "unauthenticated" });
  });

  it("rejects an empty title with field details", async () => {
    const err = await createNoteHandler("u1", { title: "" }, deps).catch((e) => e);
    expect(err).toBeInstanceOf(HttpsError);
    expect(err.code).toBe("invalid-argument");
    expect(err.details.fieldErrors.title).toBeDefined();
  });

  it("writes the note under the caller and returns its id", async () => {
    const res = await createNoteHandler("u1", { title: "Hello" }, deps);
    const snap = await db.doc(`users/u1/notes/${res.id}`).get();
    expect(snap.exists).toBe(true);
    expect(snap.data()?.tags).toEqual([]);
    expect(snap.data()?.createdAt).toBeDefined();
  });
});
```

```swift
// iOS — FirebaseBootstrap.swift (DEBUG only, before any Firebase service is used)
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseFunctions

enum FirebaseBootstrap {
  static func configure() {
    FirebaseApp.configure()
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("-useFirebaseEmulator") {
      let host = ProcessInfo.processInfo.environment["FIREBASE_EMULATOR_HOST"] ?? "127.0.0.1"
      Auth.auth().useEmulator(withHost: host, port: 9099)
      let settings = Firestore.firestore().settings
      settings.host = "\(host):8080"
      settings.isSSLEnabled = false
      settings.cacheSettings = MemoryCacheSettings()
      Firestore.firestore().settings = settings
      Functions.functions(region: "asia-southeast1").useEmulator(withHost: host, port: 5001)
    }
    #endif
  }
}
```

## Output format

If the user asks for a review, organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated.
3. Show a brief before/after code fix.

Skip files with no issues. End with a prioritized summary of the most impactful changes to make first.

If the user asks you to write or improve tests, follow the same rules but make the changes directly instead of returning a findings report.

Example output:

### functions/test/notes.test.ts

**Line 8: Admin Firestore is mocked with `vi.mock`, so the transaction and `serverTimestamp()` paths are never executed.**

```ts
// Before
vi.mock("firebase-admin/firestore", () => ({ getFirestore: () => fakeDb }));

// After — real Admin SDK against the emulator (FIRESTORE_EMULATOR_HOST is set by emulators:exec)
initializeApp({ projectId: "demo-snaptool" });
const db = getFirestore();
```

**Line 31: Trigger test sleeps a fixed 2 s and then reads — flaky under CI load.**

```ts
// Before
await db.doc("users/u1/notes/n1").set({ title: "x" });
await new Promise((r) => setTimeout(r, 2000));
expect((await db.doc("users/u1").get()).data()?.noteCount).toBe(1);

// After
await db.doc("users/u1/notes/n1").set({ title: "x" });
await waitFor(async () => (await db.doc("users/u1").get()).data()?.noteCount === 1, { timeoutMs: 5000 });
```

### firestore.rules.test.ts

**Line 3: Rules are exercised with the Admin SDK, which bypasses rules — every assertion passes vacuously.**

```ts
// Before
const db = getFirestore();          // firebase-admin
await assertSucceeds(db.doc("users/alice").get());

// After
const alice = env.authenticatedContext("alice").firestore();
await assertSucceeds(getDoc(doc(alice, "users/alice")));
```

### Summary

1. **Vacuous rules tests (high):** `firestore.rules.test.ts` cannot fail; rewrite with `@firebase/rules-unit-testing` contexts.
2. **Mocked Admin SDK (high):** the mock hides real Firestore behaviour; run under `emulators:exec`.
3. **Fixed sleep in trigger test (medium):** replace with bounded polling.

End of example.

## References

- `references/test-strategy.md` — the pyramid for a functions backend: pure logic → handler → emulator integration → rules → iOS end-to-end; what belongs at which layer, directory layout, and npm scripts.
- `references/emulator-suite.md` — `firebase.json` emulators block, ports, `emulators:start` vs `emulators:exec`, `--import` / `--export-on-exit` seed data, Emulator UI, env vars, LAN access for a physical device, and what the emulator cannot do.
- `references/unit-testing-functions.md` — vitest setup, handler/wrapper split, `fn.run()`, `firebase-functions-test` 3.x for v2 callables and Firestore events, using the emulator instead of Admin SDK mocks, params and secrets in tests.
- `references/rules-testing.md` — `@firebase/rules-unit-testing` 4.x end to end: `initializeTestEnvironment`, authenticated / unauthenticated contexts, `withSecurityRulesDisabled` seeding, `clearFirestore`, Storage rules, the emulator's rules coverage report.
- `references/integration-testing.md` — calling emulated callables with the web SDK (`connectFunctionsEmulator` + `httpsCallable`), testing Firestore / Storage triggers by writing and polling, task queues, and faking FCM.
- `references/ios-against-emulator.md` — Swift `useEmulator` setup for Auth / Firestore / Functions / Storage in DEBUG, launch-argument gating, XCUITest with seed data, and the hand-off to `xcuitest-pro`.
- `references/ci.md` — GitHub Actions job that runs `emulators:exec`, caches emulator jars, installs Java, and uploads debug logs as artifacts.

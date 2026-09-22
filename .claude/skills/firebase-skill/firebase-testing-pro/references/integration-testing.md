# Integration testing against the emulator

Layer 3. These tests exercise the deployed-to-emulator function through the same wire the iOS app uses: an HTTPS callable with a real (emulated) ID token, a Firestore write that fires a trigger, an object upload that fires a Storage trigger, a task enqueue that reaches a worker. Keep them few; they cost seconds each.

Run: `firebase emulators:exec --only functions,firestore,auth,storage --project demo-snaptool --import ./seed "vitest run --dir test/integration"`. The Functions emulator loads the compiled `lib/` — make `npm run build` part of the script (`"predeploy"`-style: `npm run build && firebase emulators:exec ...`) or point `main` in `package.json` at a tsx loader; the simplest reliable option is to build first.

## A web-SDK client that mirrors the iOS app

```ts
// test/helpers/client.ts — the web SDK plays the role of the iOS app
import { deleteApp, initializeApp, type FirebaseApp } from "firebase/app";
import { connectAuthEmulator, getAuth, signInWithEmailAndPassword, signInAnonymously, signOut, type Auth } from "firebase/auth";
import { connectFunctionsEmulator, getFunctions, httpsCallable, type Functions } from "firebase/functions";
import { connectFirestoreEmulator, getFirestore, type Firestore } from "firebase/firestore";

export interface TestClient { app: FirebaseApp; auth: Auth; functions: Functions; db: Firestore }

export function makeClient(name = `client-${Date.now()}`): TestClient {
  const app = initializeApp({ projectId: "demo-snaptool", apiKey: "fake-api-key", appId: "1:1:web:fake" }, name);
  const auth = getAuth(app);
  connectAuthEmulator(auth, "http://127.0.0.1:9099", { disableWarnings: true });
  const functions = getFunctions(app, "asia-southeast1");          // same region the iOS app passes to Functions.functions(region:)
  connectFunctionsEmulator(functions, "127.0.0.1", 5001);
  const db = getFirestore(app);
  connectFirestoreEmulator(db, "127.0.0.1", 8080);
  return { app, auth, functions, db };
}

export async function signInAs(c: TestClient, email: string, password = "password") {
  await signInWithEmailAndPassword(c.auth, email, password);      // users come from ./seed (auth_export)
}
export const signInAnon = (c: TestClient) => signInAnonymously(c.auth);
export const signOutAll = (c: TestClient) => signOut(c.auth);
export const dispose = (c: TestClient) => deleteApp(c.app);

export const call = <Req, Res>(c: TestClient, name: string) => httpsCallable<Req, Res>(c.functions, name);
```

`apiKey` must be non-empty for the Auth emulator; any string works. Give each `initializeApp` a unique `name` or vitest's module cache returns the same app across files.

## Callables

```ts
// test/integration/callables.test.ts
import { afterAll, afterEach, beforeAll, describe, expect, it } from "vitest";
import { adminDb, clearFirestore } from "../helpers/emulator.js";
import { call, dispose, makeClient, signInAnon, signInAs, signOutAll, type TestClient } from "../helpers/client.js";

let c: TestClient;
const db = adminDb();

beforeAll(() => { c = makeClient(); });
afterEach(async () => { await signOutAll(c); await clearFirestore(); });
afterAll(() => dispose(c));

describe("createNote", () => {
  it("unauthenticated → functions/unauthenticated", async () => {
    const createNote = call<{ title: string }, { id: string }>(c, "createNote");
    await expect(createNote({ title: "x" })).rejects.toMatchObject({ code: "functions/unauthenticated" });
  });

  it("invalid input → functions/invalid-argument with details", async () => {
    await signInAs(c, "alice@test.dev");
    const createNote = call<{ title: string }, { id: string }>(c, "createNote");
    const err = await createNote({ title: "" }).catch((e) => e);
    expect(err.code).toBe("functions/invalid-argument");
    expect(err.details?.fieldErrors?.title).toBeDefined();   // what iOS reads from FunctionsErrorDetailsKey
  });

  it("member creates a note that lands under their uid", async () => {
    await signInAs(c, "alice@test.dev");
    const createNote = call<{ title: string }, { id: string; createdAt: string }>(c, "createNote");
    const { data } = await createNote({ title: "From the wire" });
    expect(data.createdAt).toMatch(/^\d{4}-\d{2}-\d{2}T/);   // ISO string, never a Timestamp object
    const snap = await db.doc(`users/alice/notes/${data.id}`).get();
    expect(snap.data()?.title).toBe("From the wire");
  });

  it("an unexpected throw surfaces as functions/internal (message not leaked)", async () => {
    await signInAs(c, "alice@test.dev");
    const boom = call<{ mode: string }, unknown>(c, "debugThrow");   // a test-only function exported in non-prod builds
    const err = await boom({ mode: "raw-error" }).catch((e) => e);
    expect(err.code).toBe("functions/internal");
    expect(err.message).not.toContain("database password");
  });
});
```

The web SDK prefixes codes with `functions/`; the iOS SDK maps the same codes to `FunctionsErrorCode` (`.unauthenticated`, `.invalidArgument`, …). Testing the code on the wire once per function is what guarantees the Swift `catch` in `firebase-ios-contract` matches.

### Streaming callables

```ts
const chat = httpsCallable<{ prompt: string }, { text: string }, { text: string }>(c.functions, "chat");
const { stream, data } = await chat.stream({ prompt: "hi" });      // web SDK ≥ 11.x
const chunks: string[] = [];
for await (const chunk of stream) chunks.push(chunk.text);
expect(chunks.length).toBeGreaterThan(0);
expect((await data).text).toBe(chunks.join(""));
```

### `onRequest` endpoints

```ts
const res = await fetch("http://127.0.0.1:5001/demo-snaptool/asia-southeast1/health");
expect(res.status).toBe(200);
expect(await res.json()).toMatchObject({ ok: true });
```

## Firestore triggers — write, then poll

```ts
// test/integration/triggers.test.ts
import { beforeEach, describe, expect, it } from "vitest";
import { adminDb, clearFirestore, waitFor } from "../helpers/emulator.js";

const db = adminDb();

describe("onNoteCreated", () => {
  beforeEach(() => clearFirestore());

  it("increments users/{uid}.noteCount", async () => {
    await db.doc("users/u1").set({ noteCount: 0 });
    await db.doc("users/u1/notes/n1").set({ title: "x" });
    await waitFor(async () => (await db.doc("users/u1").get()).data()?.noteCount === 1, { timeoutMs: 5000 });
  });

  it("does not loop when the trigger writes back to the note", async () => {
    await db.doc("users/u1/notes/n1").set({ title: "x" });
    await waitFor(async () => (await db.doc("users/u1/notes/n1").get()).data()?.normalizedTitle === "x");
    await new Promise((r) => setTimeout(r, 500));                  // the one acceptable sleep: proving nothing ELSE happens
    const snap = await db.doc("users/u1/notes/n1").get();
    expect(snap.data()?.writeCount ?? 1).toBe(1);
  });
});
```

`waitFor` (from `unit-testing-functions.md`) polls every 100 ms with a hard deadline. A trigger that never fires produces a clear timeout message instead of a wrong-value assertion after a blind sleep.

Writing with the Admin SDK gives `authType: "system"` on `onDocumentCreatedWithAuthContext`. To test the `"app_user"` branch, write through the web-SDK client after `signInAs`.

## Storage triggers

```ts
import { getStorage } from "firebase-admin/storage";

const bucket = getStorage().bucket("demo-snaptool.appspot.com");   // must equal the `bucket` option on onObjectFinalized
await bucket.file("users/u1/scans/s1/page-1.jpg").save(Buffer.alloc(1024), { contentType: "image/jpeg" });
await waitFor(async () => (await db.doc("users/u1/scans/s1").get()).data()?.status === "queued");
```

`initializeApp({ projectId: "demo-snaptool", storageBucket: "demo-snaptool.appspot.com" })` in the helper if you call `bucket()` with no argument. The emulator accepts either the `.appspot.com` or `.firebasestorage.app` suffix but the trigger only fires for the bucket name it was declared with.

## Task queues

Two levels:

1. **Handler level (preferred):** `onTaskDispatched` exports have `.run(request)` — call `processScan.run({ data: { uid, scanId }, ...})` with a minimal request and assert on Firestore. Retries are the platform's job; test that the handler is idempotent by calling it twice.
2. **Emulator level:** with the `tasks` emulator enabled (`firebase.json` → `"tasks": { "port": 9499 }`), `getFunctions().taskQueue("processScan").enqueue(payload)` inside the emulated `onScanCreated` dispatches to the local `processScan`. Assert with `waitFor` on the final `status: "done"`. If enqueue fails locally with a connection error, the Tasks emulator is not running or the CLI is too old — verify against firebase docs for the CLI version pinned in CI.

```ts
it("upload → onScanCreated → processScan → status done", async () => {
  await db.doc("users/u1/scans/s1").set({ status: "uploaded", pages: 1 });
  await waitFor(async () => (await db.doc("users/u1/scans/s1").get()).data()?.status === "done", { timeoutMs: 15_000 });
});
```

Gemini / Vision inside `processScan` must be behind the `ai` dep with a fake selected by env (`process.env.AI_FAKE=1` read in `index.ts`'s deps factory) — the emulator has no way to intercept outbound HTTP.

## FCM cannot be emulated — fake `messaging`

There is no FCM emulator and `demo-` projects have no credentials, so any `getMessaging().send()` reached by an integration test fails with a credentials error. Choose one:

- **Deps injection (default):** `index.ts` builds `deps.messaging = process.env.FUNCTIONS_EMULATOR === "true" ? new RecordingMessaging(db) : getMessaging()`, where `RecordingMessaging` writes each message to `_test/outbox/{autoId}` in the emulated Firestore. The integration test then asserts on the outbox document. Unit tests use the in-memory `FakeMessaging`.
- **Observe the side effects only:** assert on what the function writes to Firestore (`notifications/{id}` with `sentAt`) and leave payload assertions to layer 1/2.

```ts
it("sharing a note records a push for the recipient", async () => {
  await signInAs(c, "alice@test.dev");
  await call<{ noteId: string; toUid: string }, void>(c, "shareNote")({ noteId: "n1", toUid: "bob" });
  await waitFor(async () => !(await db.collection("_test/outbox/messages").where("data.noteId", "==", "n1").get()).empty);
  const msg = (await db.collection("_test/outbox/messages").where("data.noteId", "==", "n1").get()).docs[0].data();
  expect(msg.apns.payload.aps["thread-id"]).toBe("n1");
});
```

Never branch on `FUNCTIONS_EMULATOR` for anything except choosing fakes for services with no emulator.

## Does not exist / common mistakes

- `connectFunctionsEmulator(functions, "http://127.0.0.1:5001")` — host and port are separate arguments.
- `getFunctions(app)` without the region when the function is deployed to `asia-southeast1` — the emulator returns `functions/not-found`.
- Asserting `err.code === "unauthenticated"` on the web SDK — it is `"functions/unauthenticated"`.
- `firebase emulators:exec "vitest"` (watch mode) — never exits; use `vitest run`.
- Running integration and unit files in the same vitest invocation with `fileParallelism` on — `clearFirestore()` from one file wipes another file's seed mid-test.
- Testing a scheduled function by waiting — schedules never fire in the emulator.
- Relying on `--import ./seed` *and* calling `clearFirestore()` in `beforeEach` — the seed is gone after the first test. Either re-seed in `beforeEach` with a script, or scope tests to fresh ids and skip the clear.

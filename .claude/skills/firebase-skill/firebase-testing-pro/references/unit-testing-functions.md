# Unit testing Functions

Layers 1 and 2 of the pyramid. Goal: run hundreds of tests in seconds, with the real Admin SDK against the Firestore/Auth emulators and no Firebase at all for pure logic.

## Project setup (vitest, ESM, Node 22)

```json
// functions/package.json (relevant parts)
{
  "type": "module",
  "engines": { "node": "22" },
  "scripts": {
    "build": "tsc",
    "test:unit": "firebase emulators:exec --only firestore,auth,storage --project demo-snaptool 'vitest run --dir test/unit'"
  },
  "dependencies": { "firebase-admin": "^13.0.0", "firebase-functions": "^6.3.0", "zod": "^3.23.0" },
  "devDependencies": { "firebase-functions-test": "^3.4.0", "typescript": "^5.6.0", "vitest": "^2.1.0" }
}
```

```ts
// functions/vitest.config.ts
import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    include: ["test/**/*.test.ts"],
    setupFiles: ["test/helpers/setup.ts"],
    fileParallelism: false,   // one shared emulator; parallel files race on clearFirestore()
    testTimeout: 15_000,
    hookTimeout: 30_000,
  },
});
```

```ts
// functions/test/helpers/setup.ts — defaults so `vitest` works outside emulators:exec too
process.env.GCLOUD_PROJECT ??= "demo-snaptool";
process.env.FIRESTORE_EMULATOR_HOST ??= "127.0.0.1:8080";
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= "127.0.0.1:9099";
process.env.FIREBASE_STORAGE_EMULATOR_HOST ??= "127.0.0.1:9199";
// params / secrets read process.env in the runtime; give them harmless values
process.env.GEMINI_API_KEY ??= "test-key";
process.env.SENTRY_DSN ??= "";
```

```ts
// functions/test/helpers/emulator.ts
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";

export const PROJECT_ID = process.env.GCLOUD_PROJECT ?? "demo-snaptool";

export function adminDb(): Firestore {
  if (getApps().length === 0) initializeApp({ projectId: PROJECT_ID });
  return getFirestore();
}

// Emulator REST endpoints — wipe state between tests
export async function clearFirestore(projectId = PROJECT_ID) {
  const host = process.env.FIRESTORE_EMULATOR_HOST!;
  const res = await fetch(`http://${host}/emulator/v1/projects/${projectId}/databases/(default)/documents`, { method: "DELETE" });
  if (!res.ok) throw new Error(`clearFirestore failed: ${res.status}`);
}

export async function clearAuth(projectId = PROJECT_ID) {
  const host = process.env.FIREBASE_AUTH_EMULATOR_HOST!;
  const res = await fetch(`http://${host}/emulator/v1/projects/${projectId}/accounts`, { method: "DELETE" });
  if (!res.ok) throw new Error(`clearAuth failed: ${res.status}`);
}

export async function waitFor(pred: () => Promise<boolean>, { timeoutMs = 5000, intervalMs = 100 } = {}) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await pred()) return;
    await new Promise((r) => setTimeout(r, intervalMs));
  }
  throw new Error(`waitFor: condition not met within ${timeoutMs} ms`);
}
```

## Separate the handler from the wrapper

The wrapper (`onCall`, `onDocumentCreated`, `onSchedule`, `onTaskDispatched`) is untestable glue: it registers with the framework, needs `initializeApp()`, and its options are only validated at deploy. Everything that can be wrong lives in the handler, so export the handler.

```ts
// src/scans/onScanCreated.handler.ts
import type { Firestore } from "firebase-admin/firestore";
import { FieldValue } from "firebase-admin/firestore";
import { logger } from "firebase-functions";

export interface ScanCreatedDeps {
  db: Firestore;
  enqueue: (payload: { uid: string; scanId: string }) => Promise<void>;
}

export async function onScanCreatedHandler(
  params: { uid: string; scanId: string },
  data: { status?: string } | undefined,
  eventId: string,
  deps: ScanCreatedDeps,
) {
  if (!data || data.status !== "uploaded") return;                 // ignore re-fires on our own status writes
  const marker = deps.db.doc(`users/${params.uid}/scans/${params.scanId}/events/${eventId}`);
  try {
    await marker.create({ handledAt: FieldValue.serverTimestamp() }); // idempotency: second delivery hits ALREADY_EXISTS
  } catch (e: unknown) {
    if ((e as { code?: number }).code === 6) { logger.info("duplicate event", { eventId }); return; }
    throw e;
  }
  await deps.enqueue({ uid: params.uid, scanId: params.scanId });
  await deps.db.doc(`users/${params.uid}/scans/${params.scanId}`).update({ status: "queued" });
}
```

```ts
// src/index.ts
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { getFunctions } from "firebase-admin/functions";
import { onScanCreatedHandler } from "./scans/onScanCreated.handler.js";

export const onScanCreated = onDocumentCreated(
  { document: "users/{uid}/scans/{scanId}", region: "asia-southeast1" },
  (event) => onScanCreatedHandler(event.params, event.data?.data(), event.id, {
    db,
    enqueue: (p) => getFunctions().taskQueue("processScan").enqueue(p),
  }),
);
```

```ts
// test/unit/onScanCreated.test.ts
import { beforeEach, describe, expect, it, vi } from "vitest";
import { adminDb, clearFirestore } from "../helpers/emulator.js";
import { onScanCreatedHandler } from "../../src/scans/onScanCreated.handler.js";

const db = adminDb();

describe("onScanCreatedHandler", () => {
  beforeEach(() => clearFirestore());

  it("enqueues once and flips status to queued", async () => {
    await db.doc("users/u1/scans/s1").set({ status: "uploaded" });
    const enqueue = vi.fn().mockResolvedValue(undefined);
    const deps = { db, enqueue };
    await onScanCreatedHandler({ uid: "u1", scanId: "s1" }, { status: "uploaded" }, "evt-1", deps);
    await onScanCreatedHandler({ uid: "u1", scanId: "s1" }, { status: "uploaded" }, "evt-1", deps); // redelivery
    expect(enqueue).toHaveBeenCalledTimes(1);
    expect((await db.doc("users/u1/scans/s1").get()).data()?.status).toBe("queued");
  });

  it("ignores documents that are not in uploaded state", async () => {
    const enqueue = vi.fn();
    await onScanCreatedHandler({ uid: "u1", scanId: "s1" }, { status: "queued" }, "evt-2", { db, enqueue });
    expect(enqueue).not.toHaveBeenCalled();
  });
});
```

## Calling the wrapped export directly with `.run()`

v2 `CallableFunction` and `CloudFunction` expose `run(request | event)` — the framework calls it, and so can a test. This needs no `firebase-functions-test`, but importing `src/index.ts` runs `initializeApp()` and registers every export, so keep it for a few "is the wiring right" tests.

```ts
import { createNote } from "../../src/index.js";

const res = await createNote.run({
  data: { title: "Hi" },
  auth: { uid: "u1", token: { role: "member" } as never },
  rawRequest: {} as never,
  acceptsStreaming: false,
});
expect(res.id).toMatch(/^[A-Za-z0-9]{20}$/);
```

The cast on `token` / `rawRequest` is honest: the handler must not read them beyond what the test provides. If the handler does, move that access into the handler function and pass it explicitly.

## firebase-functions-test 3.x for v2

Use it when you want the event builders (`makeDocumentSnapshot`, `makeChange`) or the wrapped-callable ergonomics. Online mode (no service account) works because the emulator env vars are set.

```ts
import { afterAll, describe, expect, it } from "vitest";
import firebaseFunctionsTest from "firebase-functions-test";

const test = firebaseFunctionsTest({ projectId: "demo-snaptool" });   // online: talks to the emulator via env vars
const { createNote, onNoteCreated, onNoteUpdated } = await import("../../src/index.js");  // import AFTER init

afterAll(() => test.cleanup());

describe("createNote (wrapped)", () => {
  it("returns an id for an authenticated member", async () => {
    const wrapped = test.wrap(createNote);
    const res = await wrapped({ data: { title: "Hi" }, auth: { uid: "u1", token: { role: "member" } } });
    expect(res.id).toBeDefined();
  });

  it("maps a missing auth to unauthenticated", async () => {
    const wrapped = test.wrap(createNote);
    await expect(wrapped({ data: { title: "Hi" } })).rejects.toMatchObject({ code: "unauthenticated" });
  });
});

describe("onNoteCreated (wrapped)", () => {
  it("increments noteCount", async () => {
    const snap = test.firestore.makeDocumentSnapshot({ title: "Hi" }, "users/u1/notes/n1");
    const wrapped = test.wrap(onNoteCreated);
    await wrapped({ data: snap, params: { uid: "u1", noteId: "n1" } });
    // assert on the emulator with the Admin SDK
  });

  it("onNoteUpdated sees before/after", async () => {
    const before = test.firestore.makeDocumentSnapshot({ title: "a" }, "users/u1/notes/n1");
    const after = test.firestore.makeDocumentSnapshot({ title: "b" }, "users/u1/notes/n1");
    const wrapped = test.wrap(onNoteUpdated);
    await wrapped({ data: test.firestore.makeChange(before, after), params: { uid: "u1", noteId: "n1" } });
  });
});
```

Notes:

- v2 wrapped callables take a `CallableRequest`-shaped object (`{ data, auth, app, rawRequest }`), not the v1 `(data, context)` pair.
- v2 wrapped event functions take a partial `CloudEvent`; `firebase-functions-test` fills `id`, `time`, `source`, `type`. Pass `params` explicitly — they are not derived from the snapshot path.
- Offline mode (`firebaseFunctionsTest()` with no args) does not initialise an app; `makeDocumentSnapshot` still works, but any Admin SDK call inside the handler needs your own `initializeApp({ projectId })`.
- `test.cleanup()` deletes the apps it created; without it vitest hangs on open handles.

## Mocking Admin with the emulator, not with `vi.mock`

Rule: if Firebase ships an emulator for it, use the emulator. Fake only `messaging`, AI, and external HTTP.

```ts
// test/helpers/fakes.ts
import type { Message, BatchResponse, MulticastMessage } from "firebase-admin/messaging";

export class FakeMessaging {
  sent: Message[] = [];
  multicast: MulticastMessage[] = [];
  failTokens = new Set<string>();

  async send(msg: Message) { this.sent.push(msg); return "projects/demo/messages/1"; }

  async sendEachForMulticast(msg: MulticastMessage): Promise<BatchResponse> {
    this.multicast.push(msg);
    const responses = msg.tokens.map((t) =>
      this.failTokens.has(t)
        ? { success: false, error: { code: "messaging/registration-token-not-registered", message: "gone" } as never }
        : { success: true, messageId: `m-${t}` },
    );
    return { successCount: responses.filter((r) => r.success).length, failureCount: responses.filter((r) => !r.success).length, responses };
  }
}
```

```ts
it("prunes stale tokens after a multicast", async () => {
  const messaging = new FakeMessaging();
  messaging.failTokens.add("dead");
  await db.doc("users/u1/devices/d1").set({ token: "live", platform: "ios" });
  await db.doc("users/u1/devices/d2").set({ token: "dead", platform: "ios" });
  await sendNoteSharedPush("u1", "n1", { db, messaging });
  expect(messaging.multicast[0].apns?.payload?.aps?.["thread-id"]).toBe("n1");
  expect((await db.doc("users/u1/devices/d2").get()).exists).toBe(false);
});
```

## Params and secrets in tests

- `defineString("X").value()` and `defineSecret("Y").value()` read `process.env` at call time in the runtime. Set the env var in `setupFiles` (above) before the module that declares the param is imported.
- Never assert on a real secret. If a handler needs a Gemini key, the handler should receive an `ai` dep, not the key.
- Calling `.value()` at module scope throws during deploy analysis but not in vitest — a test can pass and the deploy still fail. Keep `.value()` inside handler bodies; a lint rule or a grep in CI (`grep -n "\.value()" src/**/*.ts` outside function bodies) is cheap insurance.

## Does not exist / common mistakes

- `test.wrap(fn)(data, { auth })` — that is the v1 shape. v2 callables take one `{ data, auth }` object.
- `test.mockConfig({...})` — v1 `functions.config()` only; params are plain env vars.
- `test.firestore.exampleDocumentSnapshot()` exists but has a fixed path and data — use `makeDocumentSnapshot` so the test reads clearly.
- `jest.mock("firebase-functions")` to stub `onCall` — it hides real option validation and breaks on ESM. Test the handler.
- `vi.useFakeTimers()` around Admin SDK calls — gRPC keepalives hang; inject `now`.
- Expecting `FieldValue.serverTimestamp()` to equal a fixed value — assert `expect.any(Timestamp)` (`import { Timestamp } from "firebase-admin/firestore"`).
- `initializeApp()` with no `projectId` under vitest — `GCLOUD_PROJECT` may be unset when you run `vitest` by hand; always pass `{ projectId }`.

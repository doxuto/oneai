# Security rules testing

`@firebase/rules-unit-testing` 4.x drives the Firestore and Storage emulators through the **modular web SDK** (`firebase/firestore`, `firebase/storage`) as a given user. The Admin SDK bypasses rules and must never appear in a rules test.

```json
// functions/package.json devDependencies (or a separate rules-tests package)
{ "@firebase/rules-unit-testing": "^4.0.0", "firebase": "^11.0.0" }
```

Run under `firebase emulators:exec --only firestore,storage --project demo-snaptool "vitest run --dir test/rules"`. Under `emulators:exec` the library discovers the emulator through `FIREBASE_EMULATOR_HUB`; pass `host`/`port` explicitly anyway so the test also runs against a hand-started `emulators:start`.

## Full Firestore example

```
// firestore.rules (under test)
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function signedIn() { return request.auth != null; }
    function isOwner(uid) { return signedIn() && request.auth.uid == uid; }
    function notAnonymous() { return request.auth.token.firebase.sign_in_provider != 'anonymous'; }
    match /users/{uid} {
      allow read: if isOwner(uid);
      allow create: if isOwner(uid) && request.resource.data.keys().hasOnly(['displayName', 'createdAt']);
      allow update: if isOwner(uid) && !request.resource.data.diff(resource.data).affectedKeys().hasAny(['plan', 'role']);
      allow delete: if false;
      match /notes/{noteId} {
        allow read: if isOwner(uid);
        allow write: if isOwner(uid) && notAnonymous()
          && request.resource.data.title is string && request.resource.data.title.size() <= 200;
      }
    }
    match /{document=**} { allow read, write: if false; }
  }
}
```

```ts
// test/rules/firestore.rules.test.ts
import { readFileSync } from "node:fs";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";
import {
  assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import {
  collection, collectionGroup, deleteDoc, doc, getDoc, getDocs, query, setDoc, updateDoc, where, serverTimestamp,
} from "firebase/firestore";

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-snaptool",
    firestore: {
      rules: readFileSync("../firestore.rules", "utf8"),   // path relative to functions/
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

beforeEach(async () => {
  await env.clearFirestore();
  // Seed with rules disabled — the ONLY place Admin-like access is allowed in a rules test
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/alice"), { displayName: "Alice", createdAt: serverTimestamp(), plan: "free" });
    await setDoc(doc(db, "users/alice/notes/n1"), { title: "Alice's note" });
    await setDoc(doc(db, "users/bob"), { displayName: "Bob", createdAt: serverTimestamp(), plan: "pro" });
  });
});

afterAll(() => env.cleanup());

const alice = () => env.authenticatedContext("alice", { email: "alice@test.dev", role: "member" }).firestore();
const bob = () => env.authenticatedContext("bob").firestore();
const anon = () => env.authenticatedContext("ghost", { firebase: { sign_in_provider: "anonymous" } }).firestore();
const nobody = () => env.unauthenticatedContext().firestore();

describe("users/{uid}", () => {
  it("owner can read own profile", () => assertSucceeds(getDoc(doc(alice(), "users/alice"))));
  it("other user cannot read profile", () => assertFails(getDoc(doc(bob(), "users/alice"))));
  it("unauthenticated cannot read profile", () => assertFails(getDoc(doc(nobody(), "users/alice"))));

  it("create allows only whitelisted keys", async () => {
    const db = env.authenticatedContext("carol").firestore();
    await assertSucceeds(setDoc(doc(db, "users/carol"), { displayName: "Carol", createdAt: serverTimestamp() }));
  });
  it("create rejects plan on self-registration", async () => {
    const db = env.authenticatedContext("dave").firestore();
    await assertFails(setDoc(doc(db, "users/dave"), { displayName: "Dave", createdAt: serverTimestamp(), plan: "pro" }));
  });

  it("owner can update displayName", () => assertSucceeds(updateDoc(doc(alice(), "users/alice"), { displayName: "A." })));
  it("owner cannot escalate plan", () => assertFails(updateDoc(doc(alice(), "users/alice"), { plan: "pro" })));
  it("owner cannot escalate role", () => assertFails(updateDoc(doc(alice(), "users/alice"), { role: "admin" })));
  it("nobody can delete a profile", () => assertFails(deleteDoc(doc(alice(), "users/alice"))));
});

describe("users/{uid}/notes/{noteId}", () => {
  it("owner reads own notes collection", () => assertSucceeds(getDocs(collection(alice(), "users/alice/notes"))));
  it("other user cannot list notes", () => assertFails(getDocs(collection(bob(), "users/alice/notes"))));

  it("owner writes a valid note", () =>
    assertSucceeds(setDoc(doc(alice(), "users/alice/notes/n2"), { title: "ok" })));
  it("title over 200 chars is rejected", () =>
    assertFails(setDoc(doc(alice(), "users/alice/notes/n2"), { title: "x".repeat(201) })));
  it("non-string title is rejected", () =>
    assertFails(setDoc(doc(alice(), "users/alice/notes/n2"), { title: 42 })));
  it("anonymous user cannot write notes", () =>
    assertFails(setDoc(doc(anon(), "users/ghost/notes/n1"), { title: "hi" })));

  it("collection group query is denied — rules are not filters", () =>
    assertFails(getDocs(query(collectionGroup(alice(), "notes"), where("title", "==", "x")))));
});

describe("catch-all", () => {
  it("unknown top-level collection is denied even for signed-in users", () =>
    assertFails(getDoc(doc(alice(), "admin/config"))));
});
```

## Token options — what `authenticatedContext` accepts

The second argument is merged into the token that rules see as `request.auth.token`:

```ts
env.authenticatedContext("alice", {
  email: "alice@test.dev",
  email_verified: true,
  role: "admin",                                  // custom claim → request.auth.token.role
  firebase: { sign_in_provider: "apple.com" },    // or "anonymous", "password", "google.com"
});
```

`request.auth.uid` is the first argument. Do not put `uid` or `sub` in the options.

## "Rules are not filters" — test queries, not just documents

A query must be provably allowed for every document it could return. Test both the allowed shape and the tempting-but-denied one:

```ts
// shared collection: /notes/{noteId} with ownerId
it("owner can list own notes with a matching where clause", () =>
  assertSucceeds(getDocs(query(collection(alice(), "notes"), where("ownerId", "==", "alice")))));
it("listing all notes is denied even though the user owns some", () =>
  assertFails(getDocs(collection(alice(), "notes"))));
```

## Storage rules

```
// storage.rules
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    match /users/{uid}/{allPaths=**} {
      allow read: if request.auth != null && request.auth.uid == uid;
      allow write: if request.auth != null && request.auth.uid == uid
        && request.resource.size < 10 * 1024 * 1024
        && request.resource.contentType.matches('image/.*');
    }
  }
}
```

```ts
// test/rules/storage.rules.test.ts
import { readFileSync } from "node:fs";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";
import { assertFails, assertSucceeds, initializeTestEnvironment, type RulesTestEnvironment } from "@firebase/rules-unit-testing";
import { getBytes, ref, uploadBytes } from "firebase/storage";

let env: RulesTestEnvironment;

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: "demo-snaptool",
    storage: { rules: readFileSync("../storage.rules", "utf8"), host: "127.0.0.1", port: 9199 },
  });
});
beforeEach(async () => {
  await env.clearStorage();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await uploadBytes(ref(ctx.storage(), "users/alice/scans/s1/page-1.jpg"), new Uint8Array(16), { contentType: "image/jpeg" });
  });
});
afterAll(() => env.cleanup());

const jpeg = (bytes: number) => new Uint8Array(bytes);
const alice = () => env.authenticatedContext("alice").storage();
const bob = () => env.authenticatedContext("bob").storage();

describe("users/{uid}/**", () => {
  it("owner uploads a small jpeg", () =>
    assertSucceeds(uploadBytes(ref(alice(), "users/alice/scans/s2/page-1.jpg"), jpeg(1024), { contentType: "image/jpeg" })));
  it("owner cannot upload a pdf", () =>
    assertFails(uploadBytes(ref(alice(), "users/alice/scans/s2/doc.pdf"), jpeg(1024), { contentType: "application/pdf" })));
  it("owner cannot upload over 10 MiB", () =>
    assertFails(uploadBytes(ref(alice(), "users/alice/big.jpg"), jpeg(10 * 1024 * 1024 + 1), { contentType: "image/jpeg" })));
  it("other user cannot read", () => assertFails(getBytes(ref(bob(), "users/alice/scans/s1/page-1.jpg"))));
  it("owner can read", () => assertSucceeds(getBytes(ref(alice(), "users/alice/scans/s1/page-1.jpg"))));
});
```

`env.clearStorage()` exists alongside `clearFirestore()` and `clearDatabase()`.

## Coverage report

The Firestore emulator records which rule expressions were evaluated. After a test run against a hand-started emulator, open:

```
http://127.0.0.1:8080/emulator/v1/projects/demo-snaptool:ruleCoverage.html
```

(`:ruleCoverage` without `.html` returns JSON.) Un-hit `allow` lines are rules nobody tests; a branch that only ever evaluated to `true` has no negative test. Under `emulators:exec` the emulator is gone when the command exits — fetch the JSON at the end of the test run and save it as a CI artifact:

```ts
afterAll(async () => {
  const res = await fetch("http://127.0.0.1:8080/emulator/v1/projects/demo-snaptool:ruleCoverage");
  await writeFile("coverage/rules-coverage.json", await res.text());
  await env.cleanup();
});
```

## Checklist per `match` block

- read: owner ✓, other user ✗, unauthenticated ✗
- create: valid ✓, extra key ✗, wrong owner ✗
- update: allowed field ✓, protected field (`plan`, `role`, `ownerId`, `createdAt`) ✗
- delete: as specified (usually ✗ for everyone; server deletes via Admin)
- list/query: allowed query ✓, broad query ✗
- anonymous provider ✗ where `notAnonymous()` is used
- every custom claim used in rules (`role`) has a test with and without it

## Does not exist / common mistakes

- `firebase.initializeTestApp({...})` / `firebase.loadFirestoreRules` / `firebase.clearFirestoreData` — that is the v1 API (removed in 2.x). Use `initializeTestEnvironment`.
- `env.authenticatedContext({ uid: "alice" })` — the uid is a positional string, not an object.
- `getFirestore()` from `firebase-admin` inside a rules test — bypasses rules; every `assertSucceeds` passes and every `assertFails` fails.
- `assertFails` passing for *any* error: it only accepts permission-denied errors; a network error or a bad path rejects the test. Read the message.
- `serverTimestamp()` from `firebase/firestore` in `withSecurityRulesDisabled` is fine; from `firebase-admin/firestore` (`FieldValue.serverTimestamp()`) is a different class and will not serialise through the web SDK.
- Loading `firestore.rules` from the wrong relative path silently tests the rules the emulator loaded from `firebase.json` instead (or nothing). Assert the file exists in `beforeAll` (`readFileSync` throws — good; do not wrap it in a try/catch that falls back).
- Tests that pass with `firestore.rules` set to `allow read, write: if true` — add at least one `assertFails` per block or the suite is decorative.

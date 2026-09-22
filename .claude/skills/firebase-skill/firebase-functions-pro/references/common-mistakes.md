# Common mistakes and hallucinated APIs

Every entry: what is written, why it is wrong, what to write instead. When reviewing, quote the line and point at the entry. When writing, if an identifier is not in this bundle's fact sheet and you are not certain it exists, write "verify against firebase docs" next to it rather than guessing.

## Imports and API generation

**`import * as functions from "firebase-functions"; functions.https.onCall(...)`**
v1 API. In firebase-functions 6.x the default export is still v1 for compatibility. Use `import { onCall } from "firebase-functions/v2/https"`.

**`onCall((data, context) => ...)` / `context.auth` / `context.rawRequest`**
v1 handler signature. v2 is `onCall(options, (request) => ...)` with `request.data`, `request.auth`, `request.app`, `request.rawRequest`.

**`functions.region("x").runWith({...}).https.onCall(...)`**
v1 builder chain. v2: `onCall({ region: "x", memory: "512MiB" }, ...)` or `setGlobalOptions`.

**`import { onCreate } from "firebase-functions/v2/auth"`**
`firebase-functions/v2/auth` does not exist. Auth lifecycle triggers (`onCreate`, `onDelete`) are v1 only: `import * as functionsV1 from "firebase-functions/v1"; functionsV1.auth.user().onDelete(...)`. v2 has only blocking triggers in `firebase-functions/v2/identity` (`beforeUserCreated`, `beforeUserSignedIn`) and those need Identity Platform.

**`functions.config().gemini.key`**
Deprecated and removed for new deployments (March 2026). Use `defineString`/`defineSecret` from `firebase-functions/params` and `.value()` inside the handler.

**`import admin from "firebase-admin"; admin.initializeApp(); admin.firestore()`**
Namespaced admin still works in 13.x but drags every service into cold start. Bundle standard is modular: `import { initializeApp, getApps } from "firebase-admin/app"; import { getFirestore } from "firebase-admin/firestore"`.

**`import { onDocumentCreated } from "firebase-functions/firestore"`**
Valid in 6.x (top-level subpath is v2), but the bundle imports from `firebase-functions/v2/firestore` so the generation is explicit. Do not mix both styles in one project.

**`import { logger } from "firebase-functions/v2"`**
`logger` is exported from `firebase-functions/logger` (and from the root). `firebase-functions/v2` exports `setGlobalOptions` and option types.

**`import { HttpsError } from "firebase-functions"`**
Root export is the v1 `https.HttpsError` under a namespace, not a top-level named export. Import from `firebase-functions/v2/https`.

## Callable handler bugs

**`const uid = request.auth.uid;`**
`request.auth` is `AuthData | undefined`. TypeScript with `strict: true` rejects this; with `strict: false` it throws at runtime and surfaces as `internal`. Guard: `if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required");`.

**`onCall({ cors: true }, ...)`**
CORS is automatic for callables. `cors` is an `onRequest` option. Remove it.

**`onCall({ invoker: "public" }, ...)`**
Not a callable option. Callables are always publicly reachable; gate inside the handler.

**`request.data.title` with `CallableRequest<CreateNoteInput>` and no parse**
The generic asserts, it does not validate. Type the request as `CallableRequest<unknown>` and `parse()` with zod.

**`return snap.data()`**
Contains Firestore `Timestamp` (does not JSON-encode through the callable; the client receives `{ _seconds, _nanoseconds }` or the call fails), and every stored field including ones the client must not see. Map to an explicit output object with ISO-8601 strings.

**`return new Date()` inside a nested object**
`Date` does JSON-encode to an ISO string, so this one works — but be explicit with `.toISOString()` so the output type is `string` and the Swift `Codable` matches.

**`throw new Error("Not found")`**
Arrives at the client as `internal` / `"INTERNAL"`. Throw `new HttpsError("not-found", "Note not found")`.

**`throw new HttpsError("NOT_FOUND", ...)` / `new HttpsError(404, ...)`**
Codes are lower-case kebab-case strings from `FunctionsErrorCode`.

**`catch (err) { throw new HttpsError("internal", err.message) }`**
Leaks provider messages. Log the message; throw a generic one. And check `err instanceof HttpsError` first so deliberate codes survive.

**`response.sendChunk(...)` without checking `request.acceptsStreaming`**
Harmless but wasteful; also a sign the author did not consider non-streaming clients. Guard it, and always `return` the final value.

**`res.send()` / `res.json()` in an `onCall` handler**
Express API. Callables `return` a value.

**Handler not `async` but returns a promise chain with a dangling branch**
Make every handler `async` and `await` everything before `return`.

## Secrets and config

**`const key = GEMINI_API_KEY.value();` at module top level**
Empty during deploy-time analysis (CLI warns), frozen for the instance lifetime, breaks emulator overrides. Read inside the handler.

**`.value()` called in a function that does not list `secrets: [X]`**
Returns an empty string at runtime with no error. Declare it.

**`process.env.GEMINI_API_KEY`**
Works in production (secrets are mounted as env vars) but bypasses the deploy check and the emulator's `.secret.local`. Use `.value()`.

**Secret value in `.env`**
`.env` files are committed and shipped into the function's environment config visible in the console. Use `firebase functions:secrets:set`.

**`secrets: ["GEMINI_API_KEY"]` as a string**
Accepted, but you lose the typed `.value()` and the CLI's existence check. Pass the `defineSecret` object.

## Admin SDK

**`getMessaging().sendMulticast(...)` / `sendAll(...)`**
Removed in firebase-admin 13 (deprecated in 12). Use `sendEachForMulticast({ tokens, ... })` and `sendEach([...])`.

**`getMessaging().sendToDevice(token, payload)`**
Legacy FCM API, shut down June 2024. Use `send({ token, ... })`.

**`admin.messaging().send({ token, notification, apns: { payload: { aps: { alert: ... } } }, data: { count: 3 } })`**
`data` values must be strings. `count: "3"`.

**`initializeApp()` in every function file**
`app/duplicate-app` in tests and on emulator hot reload. One `lib/admin.ts` with `if (getApps().length === 0)`.

**`db.settings({...})` after a read**
Throws. Call it once right after `getFirestore()`.

**`ref.set(data)` with `undefined` values**
Throws unless `ignoreUndefinedProperties: true` is set. Set it once in `lib/admin.ts`, or strip undefined before writing.

**`FieldValue.serverTimestamp()` returned from a callable or used inside an array**
Sentinels only work as top-level or nested map field values in a write; they cannot go in arrays and cannot be returned.

**`db.collection("x").offset(1000).limit(20)`**
Bills every skipped document. Use `startAfter(lastSnapshot)`.

**Calling an external API inside `runTransaction`**
Transactions retry on contention; the API gets called again. Do the call before or after.

**`enforceAppCheck: true` on `onDocumentCreated` / `onSchedule`**
App Check applies to callable and HTTP functions only. For Firestore/Storage, enforce it in the console per product.

## Triggers

**Trigger writes to its own document without a guard**
`onDocumentWritten("notes/{id}")` that updates `notes/{id}` re-fires forever. Compare `before` and `after` on the fields you change and return early when they already match, or write to a different document.

**Non-idempotent trigger**
Delivery is at-least-once. Use `event.id` as a dedupe key (`webhookEvents/{eventId}.create()`), or make the write naturally idempotent (`set` with merge, `increment` guarded by a processed flag).

**`onDocumentUpdated` handler reading `event.data.after` without checking `event.data`**
`event.data` is optional in the type. Guard it.

**Firestore trigger deployed in a region the database does not support**
Deploy fails or the trigger never fires. Match the database's region (`asia-southeast1` for a Singapore database).

**Expecting the emulator to run `onSchedule` on time**
It does not. Trigger from the Emulator UI or call the exported handler in a test.

## Runtime options

**`memory: "1GB"` / `memory: 1024`**
v2 wants the binary-suffix string union: `"1GiB"`.

**`concurrency: 80` with `memory: "256MiB"` and no `cpu: 1`**
Deploy error: concurrency > 1 needs ≥ 1 CPU.

**`timeoutSeconds: 3600` on a callable**
Max 540 for callables and event functions; 3600 is `onRequest` only.

**`setGlobalOptions` in a file that is not the entry point, or after re-exports**
Imports are hoisted; the options apply to nothing. It goes at the top of `src/index.ts`.

**`region: "asia-southeast1"` repeated on every function**
Not wrong, but noise. Set it once globally; override only where it must differ.

**No `maxInstances` anywhere**
Unbounded cost on a retry storm. Set it globally.

## HTTP

**`onRequest` without `return` after `res.send()`**
Falls through and double-sends. Always `return`.

**HMAC over `JSON.stringify(req.body)`**
Key order and whitespace differ from the sender's bytes. Use `req.rawBody`.

**`===` to compare a webhook secret**
Timing side channel. `timingSafeEqual` on equal-length buffers.

**Doing the real work in the webhook handler**
Sender retries on slow responses; you double-process. Verify, dedupe, enqueue, respond 200.

**Throwing `HttpsError` inside `onRequest` and expecting a JSON error**
Not translated there. Catch and map to a status yourself.

## Client-side counterparts (flag when reviewing Swift alongside)

**`functions.httpsCallable("x").call(data)` expecting a Codable result**
Untyped `call` returns `HTTPSCallableResult` with `.data: Any`. Use `Callable<Req, Res>` from `functions.httpsCallable("x")` with generic inference, or `httpsCallable("x", requestAs:responseAs:)`.

**`Functions.functions()` without a region while the server is in `asia-southeast1`**
Defaults to `us-central1` → `not-found`. `Functions.functions(region: "asia-southeast1")`.

**Reading custom claims on iOS after `setCustomUserClaims` without a force refresh**
`try await user.getIDTokenResult(forcingRefresh: true)`.

**Setting `consumeAppCheckToken: true` on the server while the client uses default tokens**
Every second call fails with `permission-denied`/`unauthenticated`. Client must use `HTTPSCallableOptions(requireLimitedUseAppCheckTokens: true)`.

See `firebase-ios-contract` for the full client contract.

## Testing

**`test.wrap(fn)(data, { auth: { uid } })`**
v1 wrap signature. v2: `wrapped({ data, auth: { uid, token: {} } })`.

**Running unit tests against a real project**
Use `firebase emulators:exec` and a `demo-` prefixed `projectId` so the admin SDK cannot reach production.

**`@firebase/rules-unit-testing` with admin imports**
It uses the modular web SDK (`firebase/firestore`), not `firebase-admin/firestore`.

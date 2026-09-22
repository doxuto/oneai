# Distilled Ruleset from `oneai/.claude/skills/`

> **Nguồn:** sinh tự động từ việc đọc toàn bộ source ngày 2026-09-22. Ruleset bắt buộc chắt lọc từ .claude/skills (firebase-skill, flutter-skill, ios-admob-ads-skill)
> Đây là tài liệu *mô tả hiện trạng* — không sửa code theo nó, chỉ dùng làm input cho v2.

**Sources read** (all paths relative to `$HOME/mnt/oneai/.claude/skills/`):
`firebase-skill/{firebase-functions-pro, firebase-ios-contract, firebase-security-pro, firestore-data-pro, firebase-ai-pro, firebase-testing-pro, firebase-deploy-pro, fcm-push-pro}`, `flutter-skill/{dart-pro, flutter-widgets-pro, flutter-firebase-contract, flutter-testing-pro, riverpod-pro}`, `ios-admob-ads-skill/` (SKILL + all 10 references + all templates).

Everything below is quoted or paraphrased from those files. Anything I added from my own knowledge is marked **⚠️ NOT IN SKILLS**.

---

## 1. Backend mandated ruleset

### 1.1 Runtime + language

From `firebase-functions-pro/SKILL.md` (frontmatter `targets` and "Core instructions"):

- `firebase-functions` **6.x**, v2 paths only; `firebase-admin` **13.x** modular imports (`firebase-admin/app`, `firebase-admin/firestore`).
- **Node 22** — `"engines": { "node": "22" }` in `package.json` *and* `"runtime": "nodejs22"` in `firebase.json`; `firebase-deploy-pro/SKILL.md` adds "must agree" (mismatch = deploy warning or silent fallback).
- **TypeScript**, `"module": "NodeNext"`, `"moduleResolution": "NodeNext"`, `"target": "ES2022"`, `"lib": ["ES2022"]`, `"strict": true`, plus `noImplicitReturns`, `noUnusedLocals`, `esModuleInterop`, `skipLibCheck`, `sourceMap: true`, `outDir: "lib"`, `rootDir: "src"`, `include: ["src"]`, `exclude: ["test"]` (`firebase-functions-pro/references/project-layout.md`).
- `"type": "module"` + NodeNext ⇒ **`.js` extension required on every relative import** in TS source (`from "./lib/admin.js"`). "Missing `.js` … compiles, then fails at runtime with `ERR_MODULE_NOT_FOUND` on deploy."
- Validation library: **zod** (`"zod": "^3.23.0"` in the sample `package.json`).
- Tooling: `firebase-tools` **14.x** (`firebase-deploy-pro`), `firebase-functions-test` 3.x, vitest 2.x.

Principle 1 verbatim: *"**v2 only, imported from explicit paths.** `firebase-functions/v2/https`, `firebase-functions/v2/firestore`, `firebase-functions/params`, `firebase-functions/logger`. Options are the first argument object; the handler receives a single `request` / `event`. Never mix v1 … with v2."*

The single v1 exception: *"Auth user lifecycle triggers (`onCreate`/`onDelete`) are v1 only — import `firebase-functions/v1` for them and say so in a comment. `firebase-functions/v2/auth` does not exist."*

### 1.2 `onCall` usage (the mandated shape)

`firebase-functions-pro/references/callable.md`:

> *"A callable is the default way the iOS app talks to the server… Use `onRequest` only for webhooks and third-party integrations."*

Fixed handler skeleton:

```ts
export const name = onCall(
  options,                                   // always pass enforceAppCheck
  async (request: CallableRequest<T>) => {   // (request, response) for streaming
    // 1. authenticate
    // 2. validate request.data
    // 3. authorise (does this uid own this resource?)
    // 4. do work
    // 5. return a JSON-serialisable object
  },
);
```

Mandatory first two lines of every handler (`firebase-functions-pro/SKILL.md`):

1. `if (!request.auth) throw new HttpsError("unauthenticated", ...)`
2. `Schema.safeParse(request.data)` → `invalid-argument`

> *"No exceptions for 'internal' functions; there is no such thing on a public endpoint."*

`CallableRequest<T>` fields documented: `data`, `auth` (`AuthData | undefined`), `auth.uid`, `auth.token` (`DecodedIdToken` incl. `firebase.sign_in_provider` and custom claims), `app` (`AppCheckData`), `instanceIdToken`, `rawRequest`, `acceptsStreaming` (firebase-functions ≥ 6.2).

Callable-option rules:

| Option | Rule |
|---|---|
| `enforceAppCheck: true` | On **every** callable and HTTP function an iOS/Flutter client hits |
| `consumeAppCheckToken: true` | Only on sensitive, non-idempotent calls, and only when the client sends limited-use tokens |
| `secrets: [SECRET]` | Required for `SECRET.value()` to be populated |
| `cors` | *"Accepted by the type but pointless — callables answer CORS themselves. Do not set it."* |
| `invoker` | *"Not a callable option. Callables are always publicly invokable; gate in the handler."* |

Type the handler as `CallableRequest<unknown>` *"so nobody reads `request.data.x` before parsing"*.

Anonymous-user guard: `if (request.auth.token.firebase.sign_in_provider === "anonymous") throw new HttpsError("permission-denied", "Link an account to continue", { reason: "anonymous" })`.

Authorise against the document, not the input: `db.doc(\`users/${uid}/notes/${input.noteId}\`)` — *"path includes uid → cannot reach another user's note"*. Return `not-found` for both missing and inaccessible private resources when existence would leak.

### 1.3 Folder / file layout

`firebase-functions-pro/references/project-layout.md` (exact tree):

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

Rules:
- **One exported function per file**; file name == export name. *"A file must never export two functions."*
- `src/index.ts` contains `setGlobalOptions` + explicit re-exports and **nothing else**. `setGlobalOptions` must be the first statement (ES imports are hoisted). *"Do not `export *`."*
- Grouped exports (`export const notes = { create }`) deploy as `notes-create` — avoid.
- `src/lib/admin.ts` is the **only** file that calls `initializeApp()`, guarded by `getApps().length === 0`, and the only place `db.settings({ ignoreUndefinedProperties: true })` runs.
- Domain-private helpers live next to their functions in a `_shared.ts`; shared helpers in `src/lib/`.
- Naming: callables `camelCase` verb+noun (`createNote`, `redeemCode`, `chat`) — *"No `Fn`/`Function` suffix, no `api` prefix"*; triggers `on` + subject + event (`onNoteCreated`); scheduled = job description (`pruneStaleTokens`); task workers `process` + subject (`processScan`), queue name == function name; versioned callables suffix `V2`.
- `.firebaserc`: `{ "projects": { "default": "snaptool-dev", "staging": "snaptool-staging", "prod": "snaptool-prod" } }`.
- Split into multiple `codebase`s only when deploy times or dependency sets diverge.

### 1.4 How request/response schemas are defined

`firebase-ios-contract/references/shared-types.md`: *"The zod schema is the source of truth."*

**Naming convention:** TS `CreateNoteInput` / `CreateNoteOutput`; Swift `CreateNoteRequest` / `CreateNoteResponse`. Files: `functions/src/<domain>/types.ts` ↔ `Contract/Notes.swift` (Flutter equivalent: `lib/features/<domain>/data/<domain>_models.dart`).

Zod rules (`callable.md` + `shared-types.md`):
- Bound **every** string (`.max()`), **every** array (`.max()`), **every** number (`.int().min().max()`). *"Unbounded input is a cost and abuse vector."*
- `.strict()` on objects the client fully controls (reject unknown keys); default strip for forward-compatible payloads.
- Enums: `z.enum(["free","pro"])` — string literals on the wire, **never integers**.
- Dates: `z.string().datetime()` (ISO-8601), never epoch numbers.
- IDs: `z.string().min(1).max(128)`; must not contain `/`.
- Inputs: prefer `.optional()` + `.default()` over `.nullable()`.
- **Outputs** are declared as plain TS `interface`s with `string` for dates — *"Assuming `z.infer` output types are the wire types"* is listed as a mistake.
- Outputs prefer `T | null` over `T?` so the key is always present.

Shared `parse` helper (`callable.md` / `versioning.md`):

```ts
export function parse<T>(schema: ZodType<T>, data: unknown): T {
  const result = schema.safeParse(data);
  if (!result.success) {
    throw new HttpsError("invalid-argument", "Invalid input", {
      issues: result.error.issues.map((i) => ({ path: i.path.join("."), message: i.message })),
    });
  }
  return result.data;
}
```

The `versioning.md` variant of `parse` also calls `requireMinVersion(result.data.client)`.

Full type-correspondence table (`shared-types.md`) — zod → JSON → Swift; the Dart mirror is in `flutter-firebase-contract/references/models-and-serialization.md` (section 4 below).

### 1.5 The standard response envelope

`firebase-ios-contract/references/envelope-and-naming.md` — this is the canonical envelope spec:

- The SDK wraps as `{"data": …}` / `{"result": …}` on the wire; **both sides only see the inner value**.
- **Request is always an object**, never a scalar or array at the top level, even for one field. Void request = `{}`.
- **Response is always an object.** Void response = `{}`.
- **Explicitly forbidden**: `{ success: true, data: … }`, `{ error: null, result: … }`. Verbatim: *"Failure is an `HttpsError`, not a field… A `success` boolean invites the server to return 200 with `success: false` and a message, which bypasses the whole error-mapping contract."*
- **No `uid` in the request** — *"either ignored (confusing) or trusted (a security bug)"*.
- **No `action`/`type` discriminator** to multiplex operations. *"One operation, one function."*
- Never return the whole Firestore document; map to an explicit output type.
- Field naming: camelCase both sides, no `CodingKeys`/`fieldRename` remapping. Booleans `is`/`has` prefixed. IDs end in `Id` (own id is `id`). Counts end in `Count`, timestamps in `At`, durations in `Seconds`/`Millis`.
- Dates: ISO-8601 with fractional seconds and `Z`, from `Date.prototype.toISOString()` → `"2026-09-16T08:41:12.345Z"`.
- Nesting depth ≤ 3; nested objects are named types on both sides; arrays homogeneous, no tuples.
- Money: `{ amountMinor: 1990, currency: "VND" }` — integer minor units, never floats. Sizes: `sizeBytes` integers. Percentages: pick `0–100` int (`progressPercent`) or `0.0–1.0` double (`progress`), one convention per project.
- Pagination: opaque cursor only.

```ts
const ListNotesInput = z.object({
  limit: z.number().int().min(1).max(50).default(20),
  cursor: z.string().max(512).optional(),   // opaque
  sort: z.enum(["updatedAtDesc", "titleAsc"]).default("updatedAtDesc"),
});
export interface ListNotesOutput { items: NoteSummary[]; nextCursor: string | null }
```

Cursor is typically `base64url(JSON.stringify([updatedAtMillis, id]))`; the client never inspects it; the server validates it and throws `invalid-argument` on failure. Forbidden: `page: number`, `hasMore` next to `nextCursor`, `lastId` as cursor.

Return-shape rules (`callable.md`): convert `Timestamp` → `.toDate().toISOString()`, `DocumentReference` → `ref.path`, `GeoPoint` → `{ latitude, longitude }`. `null` is fine; `undefined` is dropped. Return `{}` not `undefined` for void.

### 1.6 Error code table (every code)

`firebase-functions-pro/references/errors-and-logging.md` — *"`HttpsError` is the only error type a callable should let escape."* Signature: `new HttpsError(code, message, details?)` where `details` must be plain JSON — *"no `Error` instances, no `Timestamp`, no class instances."*

| Code | HTTP | Use when | Client UX | Retry |
|---|---|---|---|---|
| `invalid-argument` | 400 | Input failed validation, malformed ID, value out of allowed set. Include `details.issues`. | Fix the form / bug in app | No |
| `unauthenticated` | 401 | `request.auth` undefined, token expired/invalid, manual token check failed. | Sign-in screen | After re-auth |
| `permission-denied` | 403 | Signed in but not allowed: wrong role, anonymous where permanent required, resource owned by someone else (when existence is not secret). | Explain what is needed (link account, upgrade) | No |
| `not-found` | 404 | Resource does not exist, or exists but the caller must not learn that. | "Not found" empty state | No |
| `already-exists` | 409 | Create on an existing key: duplicate redeem, second signup, `ref.create()` failing with code 6. | Treat as success or show conflict | No |
| `failed-precondition` | 412 | System state forbids the operation: app too old (`details.minVersion`), account not verified, subscription required, note locked. | Directed action (update app, verify email) | After the precondition is fixed |
| `resource-exhausted` | 429 | Per-user quota, rate limit, size limit. Include `details.limit`, `details.resetAt`. | Paywall / "try later" | After `resetAt` |
| `aborted` | 409 | Transaction contention after retries, optimistic-lock version mismatch. | Auto-retry once | Yes, with backoff |
| `out-of-range` | 400 | Pagination cursor past end, index out of bounds. Rare — prefer `invalid-argument`. | Bug | No |
| `unimplemented` | 501 | Feature-flagged off, or endpoint exists only in a newer server. | Hide feature | No |
| `deadline-exceeded` | 504 | Upstream (Gemini, Vision) exceeded the deadline you set. | "Took too long, retry" | Yes, once |
| `unavailable` | 503 | Upstream down, Firestore `UNAVAILABLE`, network error to a provider. | Retry banner | Yes, with backoff |
| `internal` | 500 | A bug or unexpected state. Log the cause; never explain it to the client. | Generic error | Yes, once |
| `cancelled` | 499 | Client cancelled. You rarely throw this. | — | — |
| `data-loss` | 500 | Unrecoverable corruption. Almost never. | Generic error | No |
| `unknown` | 500 | Do not throw this on purpose. | — | — |
| `ok` | 200 | Not an error. Do not throw it. | — | — |

Canonical `details` keys (documented per function): `field`, `issues`, `reason`, `limit`, `resetAt`, `minVersion`, `retryAfterSeconds`.

gRPC → `HttpsError` mapping helper (`mapFirestoreError`): `5→not-found`, `6→already-exists`, `7→permission-denied`, `8→resource-exhausted`, `9→failed-precondition`, `10→aborted`, `4→deadline-exceeded`, `14→unavailable`, default `internal` + `logger.error("firestore.unmapped", …)`. Plus a `rethrow(err, ctx)` that re-throws `HttpsError` untouched.

Provider mapping: HTTP 429 → `resource-exhausted`; 5xx/network → `unavailable`; 4xx you caused → `internal`; safety-blocked generation → `failed-precondition` with `details.reason: "safety"`.

Never leak: stack traces, file paths, provider messages, SQL, other users' Firestore paths, secret names, internal hostnames. *"Never put the caught error object into `details` (`details: err`)."*

**Structured logging** (mandated form):

```ts
logger.debug("note.create.start", { uid });
logger.info("note.created", { uid, noteId, tagCount });
logger.warn("quota.near", { uid, used: 48, limit: 50 });
logger.error("gemini.failed", { uid, model, status, error: String(err) });
```

- First arg = stable event name `domain.thing.event`, lower-case, dot-separated (grep-able as `jsonPayload.message="note.created"`).
- Second arg = flat object, depth ≤ 2.
- `uid` on every user-scoped log; **no** email, display name, prompt text, note contents, tokens, secrets.
- `console.log(obj)` banned. `logger.log(...)` does not exist — it is `logger.info`.
- Do **not** `error` on expected client mistakes (`invalid-argument`, `unauthenticated`) — floods Error Reporting.
- Log the request once, at the end, with `ms` and domain fields.

### 1.7 Auth + App Check requirements

`firebase-security-pro/SKILL.md`, layered model: *"App Check (is this my app?) → Auth (who is this?) → rules / callable checks (may they do this?) → quota (how often?) → `maxInstances` (how much can it cost me?)"*.

- Every `onCall` starts with the `request.auth` guard.
- Roles come **only** from `request.auth.token.<claim>`, set only by `getAuth().setCustomUserClaims`. *"Never trust a `role` field the client sends in `request.data` or writes to `users/{uid}`."* Claims ≤ 1000 bytes; preserve existing claims when setting (`{ ...(target.customClaims ?? {}), plan: "pro" }`).
- After `setCustomUserClaims`, the client must force-refresh the ID token; for immediate lockout call `revokeRefreshTokens(uid)` and verify with `checkRevoked: true`.
- `enforceAppCheck: true` on all client-facing functions; `consumeAppCheckToken: true` on anything mutating money/credits/quota, matched by a limited-use token on the client.
- *"App Check is not authorization and not a rules replacement. Never write `allow read: if true` 'because App Check is on'."*
- `onRequest` handlers needing identity must verify `Authorization: Bearer <idToken>` with `getAuth().verifyIdToken(token, true)` **and** the App Check header with `getAppCheck().verifyToken`. *"Never accept a uid from the body or query string."*
- Account deletion is mandatory (App Store 5.1.1(v)): client `revokeToken(withAuthorizationCode:)` → callable `deleteAccount` (verifies recent sign-in via `auth_time`, deletes Firestore/Storage data, `getAuth().deleteUser(uid)`).

### 1.8 Secrets / params handling

`firebase-functions-pro/references/config-and-secrets.md`:

- Two mechanisms, both from `firebase-functions/params`: **params** (`defineString`, `defineInt`, `defineBoolean`, `defineList`) from `.env`, and **secrets** (`defineSecret`) from Secret Manager.
- `functions.config()` / `firebase functions:config:set` — *"Deprecated, and removed for new deployments from March 2026. Never use them."*
- All declarations in **one file**, `src/lib/params.ts`.
- `.value()` **only inside a handler** (or a lazily-called getter). Top-level `.value()` returns empty during deploy-time analysis and freezes the value.
- `secrets: [SECRET]` must be declared on every function that reads it; *"A function that omits the declaration sees an empty string at runtime — no error."*
- Use the `defineSecret` object form, not the string form.
- `.env` load order (later wins): `.env` → `.env.<projectId>` → `.env.local` (emulator only, gitignored).
- Never a secret in any `.env`, including `.env.local`. Emulator secrets go in `.secret.local` (gitignored).
- Reserved key prefixes rejected: `X_GOOGLE_`, `FIREBASE_`, `EXT_`, `GCLOUD_`, plus `PORT`, `K_SERVICE`, `K_REVISION`, `K_CONFIGURATION`, `FUNCTION_TARGET`, `FUNCTION_SIGNATURE_TYPE`.
- Secrets bind at deploy → after `firebase functions:secrets:set`, **redeploy**.
- Params may drive runtime options (resolved at deploy): `minInstances: defineInt("CHAT_MIN_INSTANCES", { default: 0 })`. But **not** in `setGlobalOptions` (runs at module load).
- Memoised-singleton pattern for secret-backed clients:

```ts
let genai: GoogleGenAI | undefined;
function getGenAI(): GoogleGenAI {
  genai ??= new GoogleGenAI({ apiKey: GEMINI_API_KEY.value() });
  return genai;
}
```

- Environment detection: `process.env.FUNCTIONS_EMULATOR === "true"`, `process.env.GCLOUD_PROJECT`. But `firebase-deploy-pro`: *"No environment-specific logic in code: no `if (process.env.GCLOUD_PROJECT === ...)`; read a param instead."*

### 1.9 Runtime options

`firebase-functions-pro/references/runtime-options.md`. Full option set with types:

```ts
setGlobalOptions({
  region: "asia-southeast1",
  memory: "256MiB",            // 128MiB…32GiB, binary suffixes only
  cpu: 1,                      // number | "gcf_gen1"
  timeoutSeconds: 60,          // callable/event max 540; onRequest max 3600
  concurrency: 80,             // 1–1000, default 80; needs cpu >= 1
  minInstances: 0,
  maxInstances: 10,
  serviceAccount, vpcConnector, vpcConnectorEgressSettings,
  ingressSettings: "ALLOW_ALL",
  labels, secrets, preserveExternalChanges,
});
```

- **Region: `asia-southeast1`**, set once in `setGlobalOptions`, matching the Firestore location and the client's hard-coded region. Rationale given: colocation with Firestore; Firestore triggers must deploy in a region the DB supports; a client/server mismatch is a runtime `not-found`, not a compile error. *"Avoid `us-central1` as a default just because the starter template uses it — it is 200 ms+ from Southeast Asia."* Changing the region of an existing function is a delete+create.
- Memory/CPU table: `256MiB` (fractional CPU, forces concurrency 1) for CRUD; `512MiB` + `cpu: 1` + `concurrency: 80` for slow-upstream (Gemini) work; `1GiB` + `cpu: 1` + `concurrency: 1–4` for CPU-bound (sharp, pdf-lib).
- Concurrency shares module-level state: singletons are a feature, module-level mutable request state is a bug; one unhandled rejection takes down 80 in-flight requests.
- Timeout by function type: CRUD callable 15–30s; AI callable non-streaming 60; AI streaming 120–300; Firestore trigger 60; webhook 30; task worker 300–540; scheduled 540 (and chunk). *"Set it to slightly above the p99 you expect, not the max."* The client SDK's own timeout (iOS default 70s) must be raised in step.
- `maxInstances` — *"the single most important cost cap"*. Global `10`; raise per function when measured. Over-cap requests fail `unavailable`/429, which is what client backoff is for. Every function sets it (`firebase-deploy-pro`), with a lower explicit value on anything calling Gemini/Vision/FCM fan-out.
- `minInstances: 1` only for the one or two launch-path callables; billed continuously; drive it from a param (1 in prod, 0 in dev).
- Ingress: `ALLOW_INTERNAL_ONLY` for task workers and scheduler-only functions, combined with `invoker: "private"` on `onRequest`. Callables stay `ALLOW_ALL`.
- Do **not** restate the global region per function; **do** restate `maxInstances` on anything that fans out or spends money.

### 1.10 Idempotency

`firestore-data-pro/references/idempotency.md` — principle: *"the question is never 'how do I prevent duplicates' but 'what does the second run do'. The answer must be: nothing, or the same thing."*

Five strategies, cheapest first:
1. **Idempotent by construction** — `set` full doc, `set {merge:true}`, `update` to a computed value, `arrayUnion`, `delete`. `increment(1)` is **not** idempotent.
2. **Deterministic document id** — `users/{uid}/inbox/{shareId}`, `users/{uid}/devices/{installationId}`, `thumbnails/{objectGeneration}` + `set`/`create`.
3. **Conditional write** — compare stored state, or `ref.update(data, { lastUpdateTime: snap.updateTime })`.
4. **Event ledger** — `ref.create` on `events/{eventId}` before non-idempotent work; treat gRPC `code === 6` (ALREADY_EXISTS) as "already done". Helper `claim(key, meta)` / `release(key)` with `expiresAt` + Firestore TTL, `LEDGER_TTL_DAYS = 7`, key sanitised (`/`→`_`, ≤1400 chars).
5. **Status machine** — `queued → processing → done`, transitioned in a transaction.

Key choice: triggers → `event.id` prefixed with the function name; storage → `event.id` or `${bucket}/${name}#${generation}`; tasks → a key you generate at enqueue (`scanId:page-1`); scheduled → `${jobName}:${event.scheduleTime}` (**not** `Date.now()`); callables → the client-generated dedupe key.

**Client dedupe key for callables** (mandated): the app generates a UUID per logical operation (`requestId`), the server uses it as the deterministic doc id and `ref.create()`s; `code !== 6` rethrows, `code === 6` means the first attempt succeeded, and the same response is returned. *"Scope ledger keys by `uid` so one user cannot replay another's key."* When the result cannot be reconstructed, store the response in the ledger doc (`events/{uid}:{requestId}` → `{ response }`).

Non-idempotent side-effect checklist requiring a ledger/guard: `FieldValue.increment`, non-unique `arrayUnion`, FCM `send`, email/SMS, third-party POST, enqueueing non-idempotent work, Gemini/Vision calls (cost), auto-id doc creation, signed-URL generation, computed `setCustomUserClaims`.

Testing requirement: *"For every trigger/task/callable test: invoke twice with the same event/payload, assert the final state equals the single-invocation state and that the external mock was called once."*

### 1.11 Transactions and batch rules

`firestore-data-pro/references/transactions-and-batches.md` — decision table: `runTransaction` for read-then-write consistency; `db.batch()` (≤ 500 ops) for atomic write-only sets; `db.bulkWriter()` for hundreds-to-millions of independent writes; plain `ref.set/update/delete/create` for a single write; `FieldValue.increment` in a plain update for read-free counters; `ref.create` for create-if-absent.

`runTransaction` rules (all enforced in review):
- **All `tx.get` before any `tx.set/update/delete`** — otherwise the SDK throws.
- The callback **retries on contention** (default `maxAttempts: 5`) so it must be pure w.r.t. side effects: no push sends, no enqueues, no mutation of outer variables.
- **No non-Firestore `await` inside** (no `fetch`, no `queue.enqueue`).
- Keep it under ~10 documents.
- Don't read outside then conditionally write inside.
- Don't catch-and-swallow inside the callback.
- `readOnly: true` for a consistent multi-doc snapshot without write locks.
- `HttpsError` thrown inside is not a contention error and propagates without retry.
- Anything touching money or quota is a callable + **server** transaction, not a client transaction.

Batches: max 500 operations, no reads, atomic but not isolated, fires every trigger for every doc touched, chunk at ~400 or use BulkWriter.

BulkWriter: `db.bulkWriter({ throttling: true })` (500/50/5 ramp), `onWriteError` returning `true` only for `failedAttempts < 3` and codes `14 UNAVAILABLE` / `4 DEADLINE_EXCEEDED` / `10 ABORTED`; **always** `await bw.close()` (or `flush()`) before returning or writes are lost; `.select()` for ids-only queries; `flush()` every ~10k writes when streaming.

gRPC codes you will see: `3 INVALID_ARGUMENT`, `4 DEADLINE_EXCEEDED`, `5 NOT_FOUND`, `6 ALREADY_EXISTS`, `7 PERMISSION_DENIED` (IAM — Admin SDK bypasses rules), `8 RESOURCE_EXHAUSTED`, `9 FAILED_PRECONDITION` (missing index or update precondition), `10 ABORTED`, `14 UNAVAILABLE`.

### 1.12 Scheduled functions

`firestore-data-pro/references/scheduled-jobs.md` — `firebase-functions/v2/scheduler`, options-object form mandatory:

```ts
onSchedule({
  schedule: "0 3 * * *",
  timeZone: "Asia/Ho_Chi_Minh",   // REQUIRED
  region: "asia-southeast1",
  retryCount: 3, minBackoffSeconds: 60, maxBackoffSeconds: 600,
  maxRetrySeconds: 3600, maxDoublings: 3,
  timeoutSeconds: 540, memory: "512MiB",
  maxInstances: 1,                 // plus concurrency: 1
}, async (event) => { event.scheduleTime; event.jobName; })
```

- `timeZone` is required for anything that means "3 am for our users"; this bundle uses `"Asia/Ho_Chi_Minh"`.
- Cron is **5-field** (seconds fail at deploy). App Engine syntax also accepted.
- Overlap guard: `maxInstances: 1` is **not enough** — also `concurrency: 1`, or take a lease document `_meta/leases/{jobName}` with `expiresAt` in a transaction.
- Idempotency key is `${name}:${event.scheduleTime}`.
- **Long jobs never loop inline.** The scheduler *finds work and enqueues it*; task workers do it. Chunk by cursor, pass explicit path lists to workers (*"a fixed list of paths is deterministic and idempotent"*).
- Renaming the function orphans the Cloud Scheduler job — delete via `firebase functions:delete`.
- **The emulator never fires schedules.**
- Monitoring: alert if a job has not succeeded in `interval × 2`; write `_meta/jobs/{name}.lastSuccessAt` + an hourly watchdog; log a structured per-run summary (`processed`, `enqueued`, `ms`, `scheduleTime`).

### 1.13 Task queues

`firestore-data-pro/references/task-queues.md` — `firebase-functions/v2/tasks` + `firebase-admin/functions`.

Worker options always set `retryConfig` and `rateLimits`:

```ts
onTaskDispatched({
  region: "asia-southeast1",
  retryConfig: { maxAttempts: 5, minBackoffSeconds: 10, maxBackoffSeconds: 300, maxDoublings: 4, maxRetrySeconds: 3600 },
  rateLimits: { maxConcurrentDispatches: 6, maxDispatchesPerSecond: 2 },
  timeoutSeconds: 300, memory: "1GiB", maxInstances: 6, secrets: [GEMINI_API_KEY],
}, async (req) => { … })
```

- Return normally = success (2xx). Throw = retry. **There is no dead-letter queue** — record failures in Firestore yourself.
- A **permanent** failure must **not** throw: log, mark the status doc `failed` with a client-safe message, return.
- A worker that sees `status === "done"` returns immediately.
- Validate `req.data` with zod. Retry headers on `req.headers`: `x-cloudtasks-taskretrycount`, `x-cloudtasks-taskexecutioncount`, `x-cloudtasks-tasketa`.
- Enqueue: `getFunctions().taskQueue<T>("ocrPage").enqueue(payload, { scheduleDelaySeconds, dispatchDeadlineSeconds, id, headers })`. Payload limit **100 KB** — pass ids and Storage paths, never bytes.
- **Order matters**: write the status doc (`queued`) *then* enqueue; a sweeper re-enqueues docs stuck in `queued`. Never enqueue inside `runTransaction`.
- `dispatchDeadlineSeconds` must be ≥ work duration and ≤ the function's `timeoutSeconds`.
- The iOS/Flutter app **never** enqueues directly — it calls a callable that enqueues.
- Fan-out completion is **derived** from child docs in a transaction, not counted with `increment` from each worker.
- One queue per upstream.
- `rateLimits` is a task-queue-only option — it does not exist on `onCall`/`onRequest`.

### 1.14 Streaming callables

`firebase-functions-pro/references/callable.md` + `firebase-ai-pro/references/streaming-to-ios.md`:

- Requires `firebase-functions ≥ 6.2` (Jan 2025) and Firebase iOS SDK ≥ 11.8 (`Callable.stream(_:)`).
- Handler signature gains a second arg: `async (request, response: CallableResponse<Chunk>)`.
- **Check `request.acceptsStreaming` before `sendChunk`.**
- **Always `return` the complete result**, streaming or not. *"the iOS side treats `.result` as authoritative and chunks as preview."*
- Validate everything **before** the first `sendChunk` — *"Throwing after chunks have been sent still delivers an error to the client… so errors are cheap."*
- Chunk payloads tiny (`{ text }`), never the accumulated string.
- `timeoutSeconds` applies to the whole stream (AI streaming: 120–300, with `abortSignal` shorter).
- *"Streaming is a foreground transport"* — anything that must survive backgrounding is a task queue + status document.
- `response.write(...)` / `response.end()` do not exist on a callable.
- `onCallGenkit` is the alternative when the AI logic is a Genkit flow (`authPolicy: (auth) => !!auth?.uid`, auto-streams when the flow defines `streamSchema`).

### 1.15 Versioning strategy for callables

`firebase-ios-contract/references/versioning.md` — *"additive changes in place, breaking changes under a new name."*

**Additive (safe, same function):** add an optional request field (`.optional()`/`.default()`); add a response field (always populated); add an enum case in a *response* (only safe if the shipped client has an `unknown` fallback); accept a new enum case in a *request*; loosen validation; add a new `details` key; add a new function.

**Breaking (new function name):** rename/remove a request or response field; change a field's type; make an optional request field required; tighten validation; remove an enum case; **change semantics without changing shape** (*"the one reviewers miss"*); change region; move v1→v2.

Convention: `createNoteV2` — *"Capital V, no dot, no underscore."* Not `createNote_v2`, `createNote.v2`, `v2CreateNote`. Keep both exported; share implementation via an internal service function with thin `onCall` adapters. Comment the legacy export with its removal condition.

Deploy order: **server first, then app** for new response fields; for new request fields ship with a server default.

Deprecating fields: keep populating old + add new → new client reads new → when min supported version passes, stop populating (`null`) then remove. *"Never remove a response field in one step."* For request fields: keep accepting the old, map it server-side, log a warning with the app version.

**Minimum app version gate:** the client sends a `ClientInfo` block on **every** call:

```ts
export const ClientInfo = z.object({
  appVersion: z.string().regex(/^\d+(\.\d+){0,2}$/),
  build: z.string().max(20),
  platform: z.enum(["ios"]),
});
```

`requireMinVersion` compares against `MIN_APP_VERSION.value()` (a `defineString` param in `.env.<projectId>`) and throws `failed-precondition` with `{ reason: "appOutdated", minVersion }`. It lives inside the shared `parse()` so *"no callable forgets"*. Gate on `appVersion` (marketing version), never `build`. *"Do not use Remote Config for the force-update gate — stale cache; the server `failed-precondition` is the gate."*

Feature flags: Remote Config on the client for "not for you yet", mirrored server-side with `defineBoolean` (or a `config/features` doc with a module-level TTL cache); when off, throw `unimplemented` so the client **hides** the feature.

Retirement checklist: check Cloud Logging for calls in the last 30 days (`resource.labels.function_name="createNote"`), raise `MIN_APP_VERSION`, wait one release cycle, remove the export, deploy. Tag the server repo with the app version it was verified against.

### 1.16 Testing requirements

`firebase-testing-pro/SKILL.md`.

**Framework:** **vitest 2.x or later** (`"test": "firebase emulators:exec --only firestore,auth \"vitest run\""`), `firebase-functions-test` **3.x**, `@firebase/rules-unit-testing` **4.x**.

Seven core rules:
1. **Test the pyramid, not the emulator.** Most tests are plain TypeScript with no Firebase.
2. **Handlers are functions; wrappers are glue.** Every `onCall`/trigger body delegates to `src/<feature>/handler.ts` exporting `createNoteHandler(ctx, input, deps)`. `src/index.ts` only wraps. Unit tests import the handler.
3. **Emulator over mocks for the Admin SDK.** *"Do not `vi.mock("firebase-admin/firestore")`… a mocked Firestore proves nothing about transactions, `create()` collisions, or `serverTimestamp()`."*
4. **`demo-` project ids everywhere** (`demo-snaptool`) — the emulator refuses real Google APIs for such projects. Never a service-account JSON in tests.
5. **Rules are code and get their own tests.** Every `allow` line gets ≥1 `assertSucceeds` and ≥1 `assertFails`; *"A rules change without a test is a security change without a test."* Rules tests use the **modular web SDK** via `env.authenticatedContext(uid, claims).firestore()` — never the Admin SDK (it bypasses rules). Seed inside `env.withSecurityRulesDisabled`, `env.clearFirestore()` in `beforeEach`, `env.cleanup()` in `afterAll`. Cover: passing case, wrong user, unauthenticated.
6. **The client tests against the same emulator with the same seed** (one `seed/` export directory).
7. Mock only what has no emulator: `getMessaging()`, Gemini/`@google/genai`, third-party HTTP — injected through a `deps` object.

Additional mandated specifics:
- `fn.run(request)` on a v2 function for a direct call; `test.wrap` only when you need snapshot/change builders; `test.cleanup()` in `afterAll`.
- Integration tests: `firebase emulators:exec --only functions,firestore,auth,storage --project demo-snaptool "vitest run --dir test/integration"`, with `fileParallelism: false`.
- Trigger tests poll with a bounded timeout: `waitFor(() => …, { timeoutMs: 5000 })` — *"never `setTimeout(2000)` and hope."*
- **Scheduled functions do not fire in the emulator** — test the handler directly.
- FCM has no emulator.
- Contract tests (`shared-types.md`): snapshot `zodToJsonSchema(CreateNoteInput)` per input/output so an accidental change shows up in review.
- CI caches `~/.cache/firebase/emulators`, installs a JDK, uploads `*-debug.log` on failure.

### 1.17 Deploy (from `firebase-deploy-pro/SKILL.md`)

- One Firebase project per environment (`dev`, `staging`, `prod`) with separate Firestore, Auth, secrets, APNs keys and budgets.
- Every CLI command passes `-P <alias>` explicitly; never rely on `firebase use`.
- `firebase.json` functions entries set `codebase`, `runtime: "nodejs22"`, a `predeploy` running lint + build, and `ignore` for `node_modules`, `.git`, `*.local`, `*-debug.log`, `test/`, `coverage`.
- Deploys are `--only`-scoped and `--non-interactive` in CI.
- **Rules and indexes deploy before functions and before the app**: `--only firestore:rules,firestore:indexes,storage` then `--only functions:api`.
- Delete/rename/region-move = three steps (deploy new → migrate clients → delete old). *"Never rename in one deploy."*
- CI auth via **Workload Identity Federation** (`google-github-actions/auth@v2`); no SA JSON, no `FIREBASE_TOKEN`.
- Prod deploys only from a `v*` tag, in a GitHub `environment` with required reviewers and a `concurrency` guard.
- Alerting policies from day one: error rate > 2% over 5 min; p95 latency over budget; active instances near `maxInstances`; Cloud Billing budget at 50/90/100%.
- An unauthenticated, cheap `/health` `onRequest` with an uptime check in staging and prod.
- CHANGELOG entry + git tag per prod deploy; rollback = `git checkout vX.Y.Z && deploy`.

---

## 2. Firestore mandated ruleset

### 2.1 Data modeling

`firestore-data-pro/references/data-modeling.md`. Hard limits to design around:

| Limit | Value |
|---|---|
| Max document size | 1 MiB (1 048 576 bytes, incl. field names and path) |
| Sustained writes per document | ~1 per second |
| Max subcollection depth | 100 (2–3 is the norm) |
| Max field name / path | 1 500 bytes |
| Max indexable entries per doc | 20 000 |
| Max writes per transaction/batch | 500 |
| Max `in` / `array-contains-any` values | 30 |

**The `users/{uid}` root** — canonical layout:

```
users/{uid}                                  profile, plan mirror, counters, schemaVersion
users/{uid}/notes/{noteId}                   user content
users/{uid}/notes/{noteId}/shares/{shareId}  per-note child records
users/{uid}/scans/{scanId}                   pipeline status docs the app listens to
users/{uid}/devices/{installationId}         FCM tokens
users/{uid}/quota/{key}                      server-only counters
users/{uid}/inbox/{itemId}                   things other users sent to me (written by functions)
events/{eventId}                             idempotency ledger, TTL, server-only
_meta/{key}                                  schema/version markers, server-only
```

Top-level collections are for data not owned by one user (`orgs/{orgId}`, `publicNotes/{noteId}`, `catalog/{sku}`).

Subcollection-vs-top-level decision table, `schemaVersion` on every document type, `createdAt`/`updatedAt` on every mutable document (server-set), arrays vs maps rules (bound arrays; move maps past ~100 dynamic keys into a subcollection; never an array of objects you update individually).

**Document ids:** auto-ids by default; deterministic ids for idempotency/uniqueness; never monotonically increasing ids (index hot-spot); never user content as an id. Client-generated UUID is fine and doubles as the callable dedupe key.

**Timestamps:** `Timestamp` in documents (`FieldValue.serverTimestamp()`); ISO-8601 strings over callables; `Timestamp` for TTL fields.

**Denormalised counters:** `FieldValue.increment(n)` from the server only; rules deny-list the field; triggers must be idempotent; a scheduled job reconciles against `count()` nightly. Hot counters (>1 write/sec) get sharded (`counters/{id}/shards/{0..N}`).

**Soft delete:** `isDeleted` + `deletedAt`, filtered in every list (accept that `isDeleted` joins every composite index), purged by a scheduled job after 30 days; `allow delete: if false` when you need audit.

Explicit non-features: joins, `LIKE`/full-text search (use `>=`/`<` prefix on a lowercased field, or Algolia/Typesense via a trigger), `collection.get().size` for counting.

### 2.2 Indexes

`firestore-data-pro/references/queries-and-indexes.md`:

- Composite indexes live in `firestore.indexes.json` **in the repo** and deploy with `firebase deploy --only firestore:indexes`. *"never click-create in production only."* Deploy indexes **before** the code that needs them.
- `queryScope: "COLLECTION"` vs `"COLLECTION_GROUP"` are separate entries even for the same fields.
- `fieldOverrides` with `"indexes": []` exempts a field from single-field indexing — do this for `ocrText`, `body`, large maps.
- `"ttl": true` in a field override declares the TTL policy; otherwise `gcloud firestore fields ttls update expiresAt --collection-group=events --enable-ttl`.
- Field order: equality fields first, then the range/`orderBy` field, then implicit `__name__`.
- `firebase firestore:indexes` prints the deployed set for syncing after console experiments.
- **Cursor pagination only** — `offset()` bills skipped documents. Fetch `limit + 1` to know whether a next page exists. Opaque base64url cursors over callables.
- Aggregations: `count()`, `AggregateField.sum/average`, billed per 1 000 index entries scanned, **one-shot only** (no listener form).
- TTL deletes happen "within about 24 hours" — *"TTL is for cleanup, not for enforcing expiry; queries must still filter."* TTL deletes fire `onDocumentDeleted` with `authType: "system"`.
- Missing-index errors in a callable map to `HttpsError("internal")` with the index link logged — *"Do not return the raw message (it includes the project id and collection names)."*
- Listener cost: bill per document delivered on attach and on change, plus a minimum read per 30 min idle. Listen to **small, bounded** sets; prefer one listener on a parent summary doc over N child listeners; keep rules on listened paths free of `get()` lookups.

### 2.3 Security rules patterns

`firebase-security-pro/references/firestore-rules.md`, `rules_version = '2'`:

- Rules govern client SDK access only; **the Admin SDK bypasses them entirely**.
- Deny by default, with a trailing `match /{document=**} { allow read, write: if false; }` (and the Storage equivalent `match /{allPaths=**}`). Note the caveat: *"it cannot revoke a permissive rule above it"* — access is granted if **any** matching block allows.
- Split `read` into `get`/`list` and `write` into `create`/`update`/`delete`.
- Canonical helper set: `signedIn()`, `isOwner(uid)`, `hasRole(r)`, `isAnonymous()`, `isPermanent()`, `incoming()`, `existing()`, `changedKeys()`, `isServerTime(field)`.
- **Field allow-lists:** `incoming().keys().hasOnly([...])` on create/update; `hasAll([...])` for required.
- **Immutable / privileged fields:** `!changedKeys().hasAny(['plan','role','credits','createdAt','schemaVersion'])`.
- **Type and size validation** in rules: `is string`, `is int`, `is timestamp`, `is list`, `is map`, `is latlng`, `.size() <= N`, `in [...]`, `.matches(regex)`.
- **Server timestamps:** `incoming().createdAt == request.time` is the only way to enforce `FieldValue.serverTimestamp()`. *"Do not accept … 'for clock skew' — it just lets the client lie by a minute."*
- **Roles from custom claims** (`request.auth.token.role`), not from a `get()` on the user doc (costs a read per evaluation and is forgeable if update rules are loose).
- **Anonymous restrictions:** `request.auth.token.firebase.sign_in_provider == 'anonymous'` is the only reliable signal. *"Rules cannot count documents"* — "max N for anonymous" is a quota concern.
- **Collection groups:** `match /{path=**}/notes/{noteId}` with `resource.data.ownerId == request.auth.uid`, which forces the client query to carry `.where('ownerId','==',uid)` and the subcollection docs to denormalise `ownerId`.
- **"Rules are not filters"** — a `list` rule is evaluated against the *query*. `request.query.limit <= 100` caps enumeration.
- Server-only collections (`users/{uid}/quota/{key}`, `events/{eventId}`, `_meta/*`, `admin/*`): `allow write: if false`.
- Evaluation limits: 10 `get()`/`exists()` per single-doc request, 20 for multi-doc; 256 KB rules source.
- **Recursive wildcards on user roots are a maintenance trap** — enumerate subcollections instead.
- Deploy: `firebase deploy --only firestore:rules`, effective within ~a minute; add fields as optional first so old app versions keep working.

### 2.4 Trigger patterns (v2 triggers, idempotency keys)

`firestore-data-pro/references/triggers.md`:

- Import from `firebase-functions/v2/firestore`. Five APIs + four `…WithAuthContext` variants.
- **Always the options-object form**, with explicit `region` (matching the database location) and `maxInstances`.
- `event.data` is `undefined` for deletes and can be for `onDocumentWritten`; `onDocumentUpdated`/`onDocumentWritten` give `.before`/`.after`. Guard before dereferencing.
- `event.params` from `{name}` segments only — **no `{path=**}` wildcards**, and a trigger on `notes/{noteId}` does **not** fire for its subcollections.
- Snapshots are point-in-time, not live.
- `…WithAuthContext` gives `event.authType` (`app_user` | `system` | `service_account` | `unauthenticated` | `unknown`) and `event.authId` — used to skip loops caused by your own writes.
- **Loop guards are mandatory**: compare `before` vs `after` on the inputs *and* compare the computed output against the stored value before writing. *"Never bump `updatedAt` from a trigger that listens to updates of the same doc."* Prefer `onDocumentUpdated` over `onDocumentWritten`. *"Draw the trigger graph and check for cycles in review."*
- **Delivery is at-least-once**; `event.id` is stable across redeliveries — it is the idempotency key. Ordering is **not** guaranteed (compare `event.time` / `after.updateTime` to reject stale events).
- `retry: false` is the default; `retry: true` retries for up to 7 days — *"Use `retry: true` only for handlers that are idempotent *and* whose failure is transient."*
- **Admin writes fire triggers**, including BulkWriter, batches, transactions, `recursiveDelete`, imports and TTL deletes. A 100k-doc backfill fires 100k invocations — undeploy the trigger, make it cheap, or use a `_backfill` marker field.
- No-op writes (`set` with identical data) do **not** fire `onDocumentUpdated`.
- Error policy in triggers: throw only for transient failures you want retried; for permanent failures log `error` and return normally, and write `status: "failed", error: { code, message }` into the status document the client is watching.
- Every handler must `await` everything it starts.

Storage triggers (`onObjectFinalized`): guard on `contentType` and path shape, write derived files under a **different prefix**, never re-upload to the listened path.

---

## 3. AI/LLM mandated ruleset

From `firebase-ai-pro/SKILL.md` and its references.

### 3.1 SDK

- **`@google/genai` (`GoogleGenAI`)**. *"`@google/generative-ai` is deprecated — flag it and migrate."*
- Construct the client **inside the handler** or in a lazily-initialised module singleton; never `GEMINI_API_KEY.value()` at module top level; lazy `await import("@google/genai")` to keep cold start cheap.
- `secrets: [GEMINI_API_KEY]` on every function that uses the key. On Vertex AI (`vertexai: true`) use ADC, no key, and grant the function's SA the Vertex AI User role.
- Model tiering (`references/cost-and-limits.md`), all names in one `AI` config object:

| Tier | Model | Use |
|---|---|---|
| lite | `gemini-2.5-flash-lite` | classification, language detection, short rewrites, chat-history summaries |
| default | `gemini-2.5-flash` | OCR + extraction, summaries, Q&A, translation (`thinkingConfig.thinkingBudget: 0` for extraction) |
| pro | `gemini-2.5-pro` | multi-page reconciliation, ambiguous layouts; 5–10× cost, only where a golden set shows flash failing |

*"Model names change — check the current model list before pinning."*

### 3.2 Structured output

- *"Output is data, not prose."* Anything that feeds UI or storage uses `responseMimeType: "application/json"` **plus** `responseSchema`, and the result is **re-validated with zod** (`schema.safeParse(JSON.parse(res.text))`).
- Gemini `responseSchema` is an **OpenAPI 3.0 subset**. Supported: `type`, `format`, `description`, `nullable`, `enum`, `items`, `properties`, `required`, `propertyOrdering`, `minItems`, `maxItems`, `minimum`, `maximum`, `anyOf`. **Not supported**: `$ref`, `$schema`, `additionalProperties`, `oneOf`, `allOf`, `patternProperties`, `const`.
- zod is the source; convert with `z.toJSONSchema()` (zod 4) or `zod-to-json-schema` (`{ $refStrategy: "none", target: "openApi3" }`), then a `convert()` pass that maps types, hoists `nullable`, sets `propertyOrdering` from key order, and **drops** unsupported keys.
- Why re-validate: *"`responseSchema` guarantees shape, not content."* It cannot enforce `.max(80)`, `.datetime()`, `.min(0)`, cross-field rules, or that an enum value is one you handle.
- **Retry exactly once** on parse/validation failure, appending the validation errors to the same turn at low temperature. *"Two attempts, not five."* Do **not** retry `MAX_TOKENS` or safety blocks.
- Check `res.candidates?.[0]?.finishReason`: `SAFETY` → `failed-precondition` ("Content was blocked"); `MAX_TOKENS` → `internal` ("truncated") — *"map both to explicit `HttpsError` codes instead of letting `JSON.parse` throw."*
- Prefer `nullable` over `optional` for extracted fields (the model emits `null` explicitly rather than omitting the key).
- For pure single-label classification: `responseMimeType: "text/x.enum"` with `responseSchema: { type: Type.STRING, enum: [...] }`.
- Business rules (sum checks etc.) run **after** zod, in code, and *flag* rather than fail.

### 3.3 Streaming to the client

`references/streaming-to-ios.md` (rules are transport-agnostic):

- `onCall(options, async (request, response: CallableResponse<Chunk>) => …)`.
- Branch on `request.acceptsStreaming`; the non-streaming path is the plain `generateContent` call.
- **The handler always returns the full result.** *"The client can miss chunks (backgrounded, reconnect) but never misses the return value."*
- Chunks are tiny JSON objects (`{ text }`); never send the accumulated string.
- Errors thrown after chunks still reach the client as a stream error — *"Do not try to 'send an error chunk'."*
- Output filtering applies to the **final** answer; chunks are best-effort preview and the client replaces the preview with the final value.
- Streaming with `responseSchema` yields fragments of one JSON document — parse and validate only the concatenation at the end.
- Anything that must survive backgrounding is a task + status document, not a stream.

### 3.4 Prompting and safety

`references/prompting-and-safety.md`:

- System instruction structure per feature: `ROLE / TASK / INPUT / OUTPUT / STYLE`, exported as a constant, **never assembled from user input**.
- *"Untrusted input stays untrusted."* Defences, all required:
  1. Delimit and declare — wrap content in `<note>`/`<document>`/`<page n>`, say in the system instruction that the tags hold data, and **strip the tag strings from the content first** (`escapeForPrompt`).
  2. Structured output with `responseSchema`.
  3. No secrets in context.
  4. Least privilege on tools — the model never triggers writes; it returns a *proposal* the user confirms.
  5. Output filtering (below).
  6. Input caps + logging with `promptVersion`.
  *"Do not rely on 'the model is instructed to ignore injections' as the only layer."*
- **Output filter** before anything is returned or stored: truncate at `MAX_OUTPUT_CHARS = 20_000`; redact API-key-shaped strings (`/\b(AIza[0-9A-Za-z_-]{30,}|sk-[A-Za-z0-9]{20,})\b/g`); strip URLs unless explicitly allowed (injected phishing links); strip code fences.
- **Prompt versioning**: each prompt is a `{ id, version, model, system, temperature, buildUser() }` constant; bump `version` on every wording change; log `{ prompt, promptVersion, model }` and store `promptVersion` on persisted results. A small golden set per prompt, run on demand (`npm run eval:summarize`), **not** in CI on every push.
- *"Do not read prompts from Firestore at runtime… Whoever can edit that document controls the model."*
- `safetySettings`: keep defaults for user-facing chat; `BLOCK_ONLY_HIGH` only for OCR/extraction; never `BLOCK_NONE`; map `SAFETY` finish reasons to a user message.
- Language: pass `language` explicitly from a user setting, never a locale guess; instruct translation to preserve names/numbers/currency/dates; Vietnamese `dd/mm/yyyy` → ISO conversion stated in the system instruction; diacritic sanity check regex provided.
- PII: minimise what reaches the model; **never log content** (`logger.debug` with content only behind an unset-in-prod `AI_DEBUG_LOG` param); TTL/retention; Gemini Developer API free tier may be used for product improvement — choose Vertex AI for regulated data; never extract more than the schema needs; redact phone/ID/card patterns before persisting free text.

### 3.5 Cost control

`references/cost-and-limits.md` — *"Missing any one of these is a finding"*: per-user quota, input cap, model tier, a timeout shorter than the function's, an instance cap, a log line with token counts.

- Central `AI` config object with `models` and `limits` (`dailyCallsPerUser: 50`, `dailyPagesPerUser: 40`, `maxInputChars: 30_000`, `maxPagesPerScan: 20`, `maxImageEdgePx: 1600`, per-feature `maxOutputTokens`).
- **Quota document** `users/{uid}/quota/{yyyy-mm-dd}`, incremented in a transaction **before** the model call; not decremented if the model call fails (*"the attempt cost tokens"*). Plan limits (`free`/`pro`) come from the `plan` claim/user doc, server-written only. Rules: owner read, no client write. Throws `resource-exhausted` with `{ plan, limit, resetsAt }`. `expiresAt` + TTL policy on the quota doc. For task pipelines, consume `pages` at enqueue time.
- Input caps: `slice(0, maxInputChars)` and tell the model the text may be truncated (30k chars ≈ 8–10k tokens for vi/en); cap pages; chat history is last N turns + a running summary refreshed every ~10 turns by a flash-lite call; `countTokens` only near the context limit.
- Image downscale with `sharp`: `.rotate()` (EXIF), `resize({ width: 1600, height: 1600, fit: "inside", withoutEnlargement: true })`, `.jpeg({ quality: 80, mozjpeg: true })`. Needs ≥512 MiB and ~1s cold start — keep it out of non-image callables.
- Escalation: run flash; if `unreadableFields.length > 3` or confidence below threshold, re-run on pro once and record `model` on the result.
- Context caching (`ai.caches.create` with a `ttl`) only for a large reused prefix; log `usageMetadata.cachedContentTokenCount`.
- Timeouts/memory/instances table:

| Function | `timeoutSeconds` | `memory` | `maxInstances` | model `abortSignal` |
|---|---|---|---|---|
| classify callable | 30 | 256MiB | 20 | 20 s |
| summarize / translate | 60 | 256MiB | 20 | 45 s |
| chat streaming | 120 | 256MiB | 30 | 100 s |
| scan worker (task) | 540 | 1GiB | 5 | 300 s |

  The model `abortSignal` is **always shorter** than `timeoutSeconds`. Set `concurrency` low (10–20) for AI callables.
- One structured token log line per call with fixed keys (`promptTokens`, `outputTokens`, `thoughtTokens`, `cachedTokens`, `totalTokens`, `latencyMs`, `feature`, `uid`, `model`, `promptVersion`), plus a log-based metric and an alert.
- Budget alerts at 50/90/100%, **and** a kill switch: an `AI_ENABLED` param or a `config/ai` Firestore doc read at the top of every AI function → `unavailable` when off. *"Flipping a document is faster than redeploying when a budget alert fires at 3 a.m."*

---

## 4. Client contract (the important one)

### 4.1 Function naming (shared by both contract skills)

`firebase-ios-contract/references/envelope-and-naming.md`:

- The **deployed name is the TypeScript export name**, and it is what the client string passes. *"Keep the three identical: file name, export, client string."*
- camelCase, **verb-first, from the client's point of view**: `createNote`, `listNotes`, `redeemCode`, `chat`, `startScan`, `getBootstrap`.
- **No dots.** `httpsCallable("notes.create")` is not a deployable export; grouped exports deploy as `notes-create`. Prefix instead (`notesCreate`) if you must group — *"but plain verbs read better in the app."*
- Versioned: `createNoteV2`.
- Triggers/scheduled/task workers are **not** part of the client contract and never appear in client code.
- Keep one list of client-facing names in the client:

```swift
enum FunctionName { static let createNote = "createNote"; static let chat = "chat" }
```

```dart
abstract final class Fn {
  static const createNote = 'createNote';
  static const listNotes = 'listNotes';
  static const redeemCode = 'redeemCode';
  static const chat = 'chat';
}
```

### 4.2 Exact request/response shape

Wire form (`{"data": …}` in, `{"result": …}` out) is handled by the SDK; both sides see only the inner object. Rules restated from §1.5 — object in, object out, `{}` for void, camelCase, ISO-8601 dates, no `uid`, no `{success:…}` wrapper, no `Timestamp`/`DocumentReference`/`GeoPoint`, enums as strings, depth ≤ 3, opaque cursors, money as integer minor units.

**Server (`functions/src/notes/createNote.ts`)**, from `firebase-ios-contract/SKILL.md`:

```ts
export const NoteVisibility = z.enum(["private", "shared"]);

export const CreateNoteInput = z.object({
  title: z.string().min(1).max(200),
  body: z.string().max(20_000).default(""),
  visibility: NoteVisibility.default("private"),
  tags: z.array(z.string().min(1).max(30)).max(10).default([]),
});

export interface CreateNoteOutput {
  id: string;
  title: string;
  visibility: z.infer<typeof NoteVisibility>;
  createdAt: string;   // ISO-8601
  tags: string[];
}

export const createNote = onCall(
  { enforceAppCheck: true, timeoutSeconds: 30 },
  async (request: CallableRequest<unknown>): Promise<CreateNoteOutput> => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required");
    const uid = request.auth.uid;
    const input = parse(CreateNoteInput, request.data);
    const ref = db.collection(`users/${uid}/notes`).doc();
    const now = new Date();
    await ref.set({ ...input, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });
    return { id: ref.id, title: input.title, visibility: input.visibility, createdAt: now.toISOString(), tags: input.tags };
  },
);
```

**Optionality mapping (server → client)**, from `envelope-and-naming.md` and `flutter-firebase-contract/references/models-and-serialization.md`:

| Server (zod input) | Meaning | Swift request | Dart request |
|---|---|---|---|
| `z.string()` | required | `let x: String` | `final String x;` |
| `z.string().optional()` | key may be absent | `var x: String? = nil` | `final String? x;` — **omit the key from `toJson` when null** |
| `z.string().nullable()` | present, may be `null` | `let x: String?` + null-writing encoder (avoid) | `final String? x;` — always write the key (avoid) |
| `z.string().default("")` | absent ⇒ server fills | `var x: String = ""` | `final String x;` with a Dart default |
| `z.number().int()` | int | `Int` | `final int x;` |
| `z.number()` | double | `Double` | `final double x;` — decode via `as num` |
| `z.enum([...])` | closed set | `enum X: String, Codable` | `enum X { … }` |
| `z.string().datetime()` | ISO-8601 | `Date` (custom strategy) | `final DateTime x;` |

| Server output | Swift | Dart |
|---|---|---|
| `x: string` | `let x: String` | `final String x;` |
| `x: string \| null` | `let x: String?` | `final String? x;` |
| `x?: string` | `let x: String?` (prefer `\| null`) | `final String? x;` (prefer `\| null`) |

The Dart doc stresses the asymmetry explicitly: *"`{'cursor': null}` against a `z.string().optional()` field is an `invalid-argument` the app cannot see coming."*

```dart
Map<String, Object?> toJson() => {
      'title': title,
      if (cursor != null) 'cursor': cursor,   // .optional() — omit when absent
      'sort': sort.name,
    };
```

**Enums** — response enums need a tolerant decoder on both sides:

```swift
enum JobStatus: String, Codable, Equatable, Sendable {
  case queued, processing, done, failed, unknown
  init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    self = JobStatus(rawValue: raw) ?? .unknown
  }
}
```

```dart
enum JobStatus {
  queued, processing, done, failed, unknown;
  static JobStatus fromJson(Object? raw) =>
      values.firstWhere((v) => v.name == raw, orElse: () => unknown);
  String toJson() => name;
}
```

*"`values.byName(raw)` throws on an unknown value — that is the bug this pattern exists to avoid."* Put `unknown` last and never send it. Request enums need no fallback (`z.enum` is closed). When a Dart member collides with a keyword (`private`), use a wire-value enum:

```dart
enum Visibility {
  personal('private'), shared('shared'), unknown('unknown');
  const Visibility(this.wire);
  final String wire;
  static Visibility fromJson(Object? raw) =>
      values.firstWhere((v) => v.wire == raw, orElse: () => unknown);
  String toJson() => wire;
}
```

**Discriminated unions** (`shared-types.md`): flat `type` discriminator with sibling fields, produced by `z.discriminatedUnion("type", [...])`, decoded in Swift into an enum with associated values plus an `.unknown(type:)` case. *"Use a flat `type` discriminator with sibling fields, not a wrapper key per case."*

### 4.3 Dart-side patterns (`flutter-firebase-contract`)

**Version matrix** (verified pub.dev 2026-09-22, `references/setup.md`) — *"Bump the whole block or none of it."*

| Package | Version | Requires |
|---|---|---|
| `firebase_core` | 4.15.0 | — |
| `cloud_functions` | 6.5.0 | `firebase_core ^4.14.0` |
| `cloud_firestore` | 6.10.0 | `firebase_core ^4.14.0` |
| `firebase_auth` | 6.7.0 | `firebase_core ^4.14.0` |
| `firebase_messaging` | 16.7.0 | `firebase_core ^4.14.0` |
| `firebase_app_check` | 0.4.8 | `firebase_core ^4.14.0` |
| `flutterfire_cli` | 1.4.1 | installed globally |

SDK constraints: `sdk: ^3.13.0`, `flutter: ">=3.47.0"`. Platform minimums: iOS **15**, Android **API 23**, macOS 10.15.

**`main()` initialisation order** (strict):

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseAppCheck.instance.activate(
    providerApple: kDebugMode
        ? const AppleDebugProvider()
        : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    providerAndroid: kDebugMode
        ? const AndroidDebugProvider()
        : const AndroidPlayIntegrityProvider(),
  );
  // emulator wiring
  runApp(const ProviderScope(child: MyApp()));
}
```

1. `ensureInitialized()` first. 2. `initializeApp` awaited before touching any Firebase service. 3. **App Check after `initializeApp`** — *"the opposite of the native iOS SDK… Do not port that rule into Dart."* 4. Emulator wiring after init, before the first request. 5. `runApp` last.

`firebase_options.dart` is generated by `flutterfire configure`, committed, never edited; **one file per flavour via `--out`**, never one file with a runtime `if (flavor == …)` switch. Both generated files declare `DefaultFirebaseOptions`, so import exactly one per entry point (`main_dev.dart`, `main_prod.dart`, shared `bootstrap.dart`).

**Getting the instance:**

```dart
final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
```

*"`FirebaseFunctions.instance` is `us-central1`; a mismatch is `not-found` on every call"* — and it reads like the function does not exist, because from that region it does not.

**`HttpsCallableOptions` — the whole surface is three fields:**

```dart
const HttpsCallableOptions({
  Duration timeout = const Duration(seconds: 60),
  bool limitedUseAppCheckToken = false,
  AbortSignal? webAbortSignal,   // web only
});
```

No `region`, no `appCheck`, no `retry`, no `headers`. Lower `timeout` to 15–20s for CRUD; never below the server's `timeoutSeconds` for slow calls (*"the client gives up first and reports `deadline-exceeded` while the server keeps running and commits its writes"*).

**Calling — the single most emphasised Dart rule:**

```dart
final result = await callable.call<Map<String, dynamic>>(request.toJson());
final response = CreateNoteResponse.fromJson(result.data);
```

> *"**`T` is not checked.** The implementation is `HttpsCallableResult<T>._(await delegate.call(parameters))` — a raw assignment. `call<CreateNoteResponse>()` compiles and throws `TypeError` the first time it runs. The only safe `T` values are the ones the wire can actually produce: `Map<String, dynamic>`, `List<dynamic>`, `String`, `num`, `bool`, `void`."*

Parameters must already be JSON — always pass `request.toJson()`. A `DateTime`, `Enum`, `Timestamp` or model object fails a debug assertion and produces a platform exception in release.

**The three decoding traps** (from the method-channel converter):

| Trap | Why | Correct form |
|---|---|---|
| `json['tags'] as List<String>` | converter produces `List<dynamic>` | `(json['tags'] as List).cast<String>()` |
| `json['score'] as double` | JSON `7` decodes to `int`, `7.0` to `double` | `(json['score'] as num).toDouble()` |
| `json['items'] as List<Map<String, dynamic>>` | outer list is `List<dynamic>` | `[for (final e in json['items'] as List) Item.fromJson(e as Map<String, dynamic>)]` |

*"The `double` trap is the one that survives review: a server field that happens to hold `0` in every test fixture and `0.5` in production crashes only in production."*

**Dates:** `DateTime.parse(json['createdAt'] as String)` in; `date.toUtc().toIso8601String()` out. `DateTime.parse` with `Z` gives a UTC `DateTime` — call `.toLocal()` at display time, never at decode. Encode with `.toUtc()` first or `z.string().datetime()` rejects it. `DateTime.tryParse` for anything the server may omit.

**Typed wrapper** (mandated shape):

```dart
final class FunctionsApi {
  FunctionsApi(this._functions);
  final FirebaseFunctions _functions;

  Future<R> call<R>(
    String name, {
    required Map<String, Object?> request,
    required R Function(Map<String, dynamic> json) decode,
    Duration timeout = const Duration(seconds: 20),
    bool limitedUse = false,
  }) async {
    final callable = _functions.httpsCallable(name,
      options: HttpsCallableOptions(timeout: timeout, limitedUseAppCheckToken: limitedUse));
    try {
      final result = await callable.call<Map<String, dynamic>>(request);
      return decode(result.data);
    } on FirebaseFunctionsException catch (e, s) {
      Error.throwWithStackTrace(ApiFailure.fromFunctions(e), s);
    } on TypeError catch (e, s) {
      Error.throwWithStackTrace(DecodingFailure(debugMessage: '$e'), s);
    }
  }
}
```

**Cancellation:** *"There is no `cancel()` on `HttpsCallable`."* `Future.timeout` does not cancel either — use `HttpsCallableOptions.timeout`. A `stream()` subscription **is** cancellable.

### 4.4 The sealed failure type + error mapping (Dart)

`flutter-firebase-contract/references/error-mapping.md`. Three layers: server `HttpsError` → `FirebaseFunctionsException` (`code` = lowercase hyphenated string, `message` = developer text, `details` = `dynamic`) → sealed `ApiFailure`.

| `HttpsError` code | `FirebaseFunctionsException.code` | `ApiFailure` | Retry | UX |
|---|---|---|---|---|
| `invalid-argument` | `'invalid-argument'` | `InvalidArgumentFailure` | No | Client bug; log `details.issues`, generic error |
| `unauthenticated` | `'unauthenticated'` | `UnauthenticatedFailure` | After re-auth | Route to sign-in; keep the draft |
| `permission-denied` | `'permission-denied'` | `PermissionDeniedFailure` | No | Explain using `details.reason` |
| `not-found` | `'not-found'` | `NotFoundFailure` | No | Empty state / pop the route |
| `already-exists` | `'already-exists'` | `AlreadyExistsFailure` | No | Treat as success or "already done" |
| `failed-precondition` | `'failed-precondition'` | `PreconditionFailure(reason)` | After fixing | `minVersion` → update gate; `emailUnverified`; `subscriptionRequired` → paywall |
| `resource-exhausted` | `'resource-exhausted'` | `QuotaExceededFailure(resetAt)` | After `resetAt` | Paywall / "try again at …" |
| `aborted` | `'aborted'` | `ConflictFailure` | Once, immediately | Silent retry once, then show conflict |
| `out-of-range` | `'out-of-range'` | `InvalidArgumentFailure` | No | Same as invalid-argument |
| `unimplemented` | `'unimplemented'` | `FeatureUnavailableFailure` | No | Hide the feature |
| `deadline-exceeded` | `'deadline-exceeded'` | `TransientFailure` | Backoff | "Taking too long" + retry |
| `unavailable` | `'unavailable'` | `TransientFailure` | Backoff | Offline banner / retry |
| `internal` | `'internal'` | `ServerFailure` | Once | Generic; log for support |
| `cancelled` | `'cancelled'` | `CancelledFailure` | — | Ignore |
| `unknown`, `data-loss` | `'unknown'`, `'data-loss'` | `ServerFailure` | Once | Generic |
| **transport error, no server code** | `'unavailable'` / `'deadline-exceeded'` | `TransientFailure` | Backoff | Offline banner |

**The Dart-specific row is load-bearing.** Verbatim: *"The iOS SDK reports an offline call as an `NSURLErrorDomain` error and the app maps it to a separate `network` case. The Flutter plugin does not: on Android the platform code turns a socket `IOException` into `unavailable`, and a cancelled or timed-out `IOException` into `deadline-exceeded`, explicitly 'to match iOS & Web'."* Therefore: no separate network domain; offline is `'unavailable'`; *"Do not write `if (e is SocketException)` around a callable; it will not fire."* Unrecognised codes → `ServerFailure`, never success.

**The sealed type** (must live in one file, `lib/core/api_failure.dart`, because a sealed class can only be extended from the same library):

```dart
sealed class ApiFailure implements Exception {
  const ApiFailure({this.details, this.debugMessage = ''});
  final ApiErrorDetails? details;
  final String debugMessage;   // server `message` — logs only, never UI

  factory ApiFailure.fromFunctions(FirebaseFunctionsException e) {
    final details = ApiErrorDetails.tryFrom(e.details);
    final message = e.message ?? '';
    return switch (e.code) {
      'invalid-argument' || 'out-of-range' => InvalidArgumentFailure(details: details, debugMessage: message),
      'unauthenticated' => UnauthenticatedFailure(details: details, debugMessage: message),
      'permission-denied' => PermissionDeniedFailure(details: details, debugMessage: message),
      'not-found' => NotFoundFailure(details: details, debugMessage: message),
      'already-exists' => AlreadyExistsFailure(details: details, debugMessage: message),
      'failed-precondition' => PreconditionFailure(details: details, debugMessage: message),
      'resource-exhausted' => QuotaExceededFailure(details: details, debugMessage: message),
      'aborted' => ConflictFailure(details: details, debugMessage: message),
      'unimplemented' => FeatureUnavailableFailure(details: details, debugMessage: message),
      'deadline-exceeded' || 'unavailable' => TransientFailure(details: details, debugMessage: message),
      'cancelled' => CancelledFailure(details: details, debugMessage: message),
      _ => ServerFailure(details: details, debugMessage: message),
    };
  }

  bool get isRetryable => switch (this) {
        TransientFailure() || NetworkFailure() || ServerFailure() || ConflictFailure() => true,
        _ => false,
      };

  String? get reason => details?.reason;
}
```

Subtypes (one line each, same file): `InvalidArgumentFailure`, `UnauthenticatedFailure`, `PermissionDeniedFailure`, `NotFoundFailure`, `AlreadyExistsFailure`, `PreconditionFailure`, `ConflictFailure`, `FeatureUnavailableFailure`, `TransientFailure`, `ServerFailure`, `NetworkFailure`, `CancelledFailure`, `DecodingFailure`, `UnknownFailure`, plus `QuotaExceededFailure` with `DateTime? get resetAt => details?.resetAt;`.

**`ApiErrorDetails`** decodes leniently: `reason`, `minVersion`, `limit` (`as num?)?.toInt()`), `resetAt` (`DateTime.tryParse`), `retryAfterSeconds`, `field`, `issues` (list of `ApiIssue{path, message}`). Guard with `raw is Map`, not a cast — *"`details` is `dynamic` and may be `null`, a `String`, or a `List`."*

**Conversion at the boundary, once per repository**, always with `Error.throwWithStackTrace` (*"preserves the original stack trace, which `throw` would replace"*).

**Retry helper** with injected `sleep` and `random` (*"what keeps the retry test instant and deterministic"*): `maxAttempts = 3`, honour `retryAfterSeconds`, otherwise `250ms * (1 << attempt)` + up to 300ms jitter. Never retry `InvalidArgumentFailure`, `PermissionDeniedFailure`, `NotFoundFailure`, `AlreadyExistsFailure`, `PreconditionFailure`, `QuotaExceededFailure` before `resetAt`, `UnauthenticatedFailure` before re-auth. *"Non-idempotent callables must not auto-retry `TransientFailure`… When in doubt, generate the id on the client."*

**Presentation:** copy keyed on failure type + `details.reason`, localised:

```dart
String messageFor(ApiFailure failure, AppLocalizations l10n) => switch (failure) {
      TransientFailure() || NetworkFailure() => l10n.errorConnection,
      QuotaExceededFailure(:final resetAt) when resetAt != null => l10n.errorQuotaUntil(resetAt),
      QuotaExceededFailure() => l10n.errorQuota,
      PreconditionFailure(reason: 'appOutdated') => l10n.errorUpdateRequired,
      PreconditionFailure() => l10n.errorPrecondition,
      PermissionDeniedFailure() => l10n.errorNoAccess,
      NotFoundFailure() => l10n.errorGone,
      UnauthenticatedFailure() => l10n.errorSignInRequired,
      _ => l10n.errorGeneric,
    };
```

*"A `default:` arm in a failure `switch` inside the data layer — defeats the exhaustiveness the sealed class exists for"* (only acceptable in presentation).

Testing the mapping needs no network: `FirebaseFunctionsException`'s constructor is public — `FirebaseFunctionsException({required String message, required String code, StackTrace? stackTrace, dynamic details})`.

### 4.5 Streaming from Dart

```dart
sealed class StreamResponse<T, R> {}
final class Chunk<T, R> extends StreamResponse<T, R> { final T partialData; }
final class Result<T, R> extends StreamResponse<T, R> { final HttpsCallableResult<R> result; }
```

```dart
final stream = callable.stream<Map<String, dynamic>, Map<String, dynamic>>({'prompt': prompt});
await for (final event in stream) {
  switch (event) {
    case Chunk(:final partialData): yield ChatEvent.delta(partialData['text'] as String);
    case Result(:final result):     yield ChatEvent.completed(result.data['text'] as String);
  }
}
```

- `T` = each `sendChunk` payload shape, `R` = the final return shape; **both are unchecked casts** — use `Map<String, dynamic>` for both and decode yourself.
- `Result` arrives once, last. If the server throws after chunks, the stream errors and `Result` never arrives — *"keep what was streamed and surface the failure alongside it."*
- Cancelling the subscription tears down the event channel; each `stream()` gets its own channel id so concurrent calls don't collide.
- A streaming server callable still returns, so the same function can be invoked with plain `call()`.

### 4.6 `withConverter` (Firestore streams)

`references/firestore-streams.md`:

```dart
final notesRef = FirebaseFirestore.instance
    .collection('users/$uid/notes')
    .withConverter<Note>(
      fromFirestore: (snapshot, _) => Note.fromFirestore(snapshot),
      toFirestore: (note, _) => note.toFirestore(),
    );

Stream<List<Note>> watchNotes() => notesRef
    .orderBy('updatedAt', descending: true)
    .limit(50)
    .snapshots()
    .map((q) => [for (final doc in q.docs) doc.data()]);
```

- `withConverter` returns a **new** `CollectionReference<T>`/`Query<T>`; apply it **before** `orderBy`/`where`/`limit`.
- **Inside `fromFirestore`, `Timestamp`/`DocumentReference`/`GeoPoint` *are* present** — *"That is the difference from a callable: this is the Firestore wire format, not JSON."* Convert `Timestamp` → `DateTime` there and let nothing above see it.
- Write `FieldValue.serverTimestamp()`, never a client `DateTime`.
- Decode defensively (`as String? ?? ''`) — *"A converter that throws takes the whole stream down with an error."*
- Index errors arrive as `FirebaseException(plugin: 'cloud_firestore', code: 'failed-precondition')` **on the stream's error channel**; follow the console link once and commit the entry to `firestore.indexes.json`.
- Pagination with `startAfterDocument` + `get()` (not `snapshots()`); every `orderBy` field must be present on the cursor document and the chain must match.
- `snapshots(includeMetadataChanges: true)` for save indicators (`metadata.hasPendingWrites`, `metadata.isFromCache`). *"A `set`/`update` resolves its `Future` only when the server acknowledges it. Offline, that `Future` never completes — it does not throw. Never `await` a Firestore write to drive a progress spinner."*
- `Settings(persistenceEnabled: false, cacheSizeBytes: …)` is set once, before any Firestore use.
- Listener lifecycle: never open a listener from `build()`; never rebuild the query expression in a `StreamBuilder`'s `stream:`; cancel user-scoped listeners **before** sign-out (otherwise a burst of `permission-denied`).
- Long jobs: callable returns `jobId` → task worker writes `users/{uid}/jobs/{jobId}` → app listens.

### 4.7 Auth + App Check (Dart)

`references/auth-and-appcheck.md`:

- The SDK attaches the ID token and App Check token automatically. *"You never build an `Authorization` header and you never put a `uid` in the request body."* Do **not** pre-check `currentUser` in the repository and throw locally — the server is the source of truth.
- Stream choice: `authStateChanges()` for **routing only**; `idTokenChanges()` when you must react to a new token (it fires roughly hourly — *"a router that rebuilds on it thrashes"*); `userChanges()` only where a local profile edit must show immediately.
- Never gate the first route on a synchronous `currentUser` read — it is `null` until the session is restored.
- Custom claims: `getIdTokenResult(true)` — **positional**, not named. Force a refresh immediately after any callable whose job is to change a claim, *"Otherwise the very next call fails `permission-denied` for no visible reason."* Better: have the server return the new entitlement in the response and refresh in the background.
- Anonymous: `signInAnonymously()`; `linkWithCredential` preserves the `uid`; handle `credential-already-in-use` deliberately (*"it is data loss"*); anonymous accounts are deleted after 30 days of inactivity with auto-cleanup on. Server signals an anonymous-only restriction with `permission-denied` + `details.reason == 'anonymous'` → the app shows "link your account", **not** the sign-in screen.
- App Check providers (write against the **provider classes**, not the deprecated enums):

| Platform | Release | Debug |
|---|---|---|
| iOS / macOS | `AppleAppAttestProvider()` or `AppleAppAttestWithDeviceCheckFallbackProvider()` | `AppleDebugProvider({String? debugToken})` |
| Android | `AndroidPlayIntegrityProvider()` | `AndroidDebugProvider({String? debugToken})` |
| Web | `ReCaptchaEnterpriseProvider(siteKey)` / `ReCaptchaV3Provider(siteKey)` | `WebDebugProvider()` |

  `androidProvider`/`appleProvider`/`webProvider` are deprecated. `AndroidProvider.safetyNet` does not exist. App Attest needs iOS 14+ and does not work on the simulator.
- Limited-use tokens: `HttpsCallableOptions(limitedUseAppCheckToken: true)` **only** where the server sets `consumeAppCheckToken: true`. *"Use it for purchases, redemptions, invite acceptance and account deletion — not for reads."* The Swift spelling `requireLimitedUseAppCheckTokens` does not exist in Dart.
- The full "every callable fails `unauthenticated` while signed in" debug checklist (7 items) — debug tokens per device, reinstall invalidates them, Play Integrity needs the signing SHA-256, App Attest not on simulator, **the Functions emulator does not enforce App Check**, enforcement is per product in the console.
- *"Never ship a debug provider in a release build. Gate on `kDebugMode`, not on a `--dart-define` that someone can forget."*

### 4.8 Emulator (Dart)

| Product | Call | Port |
|---|---|---|
| Functions | `FirebaseFunctions.instanceFor(region: r).useFunctionsEmulator(host, port, {automaticHostMapping = true})` | 5001 |
| Firestore | `FirebaseFirestore.instance.useFirestoreEmulator(host, port, {sslEnabled = false, automaticHostMapping = true})` | 8080 |
| Auth | `FirebaseAuth.instance.useAuthEmulator(host, port, {automaticHostMapping = true})` | 9099 |

- Gate on `const bool.fromEnvironment('USE_FIREBASE_EMULATOR')` with `EMULATOR_HOST` also a `--dart-define` — *"not on `kDebugMode` alone: debug builds that talk to the real dev project are a normal thing to want."*
- `automaticHostMapping` rewrites `localhost` → `10.2.2` on the Android emulator. A **physical device** needs the LAN IP *and* `"host": "0.0.0.0"` per emulator in `firebase.json`.
- `Firebase.initializeApp(demoProjectId: 'demo-myapp')` **overrides** `options` — use it for an emulator-only entry point.
- `firebase emulators:start --import=./seed --export-on-exit=./seed`; run the **whole suite**, never one emulator.
- What the emulator cannot tell you: App Check enforcement, composite indexes, cold starts / real timeouts, quotas and `resource-exhausted`, real FCM delivery, production rules under real claims.
- **Where to test what:**

| Layer | How |
|---|---|
| `fromJson`/`toJson` of every request/response | plain `dart test` against literal JSON copied from a real response |
| `ApiFailure.fromFunctions` | plain `dart test` constructing `FirebaseFunctionsException` directly, one test per table row |
| Notifiers/blocs and widgets | `flutter_test` with the **repository** faked |
| Repository against real callables | `integration_test`, app pointed at the emulator suite |
| Security rules | server side, `@firebase/rules-unit-testing` |

  *"The fake goes in at the repository interface, never at `FirebaseFunctions`. Mocking `FirebaseFunctions` means mocking `HttpsCallable` and `HttpsCallableResult` and re-implementing the plugin's decoding, which is exactly the code you are trying not to trust."*
- The one contract test worth having, per callable, against the emulator in CI — it *"catches a renamed field, a changed date format, a new enum value, a wrong region, and a response type the app cannot decode — the five ways a contract actually breaks"*, with `expect(response.visibility, isNot(NoteVisibility.unknown))` as *"the cheapest possible detector for 'the server added an enum case'."*

### 4.9 Layering (Dart, framework-agnostic half)

```
presentation/   widgets              — sees domain state and ApiFailure
application/    providers/notifiers  — sees the repository interface
data/           repository impl      — the ONLY layer importing cloud_functions / cloud_firestore
```

*"A widget that imports `package:cloud_functions/cloud_functions.dart` is a finding regardless of what it does with it."* The repository interface speaks in domain types and throws `ApiFailure` — *"it mentions no Firebase type, not even in a generic argument."* `FirebaseFunctions` and `FirebaseFirestore` are **constructor-injected**, not reached via `.instance` inside methods — *"That is what makes the emulator wiring, the region and the test doubles a single decision at composition time."*

### 4.10 FCM (client-facing obligations)

`fcm-push-pro/SKILL.md` + `flutter-firebase-contract/SKILL.md`:

- Token registry: `users/{uid}/devices/{installationId}` with `{ token, platform, appVersion, locale, updatedAt }`. **Never an array on the user document.** `updatedAt` refreshed on every launch and every token refresh; pruned after 60 days by a scheduled job; deleted immediately on `messaging/registration-token-not-registered` / `messaging/invalid-registration-token`.
- `data` values are **strings**; serialise numbers/booleans yourself; no nested objects. The app routes on `data.type` and never parses alert text.
- Visible push: `apns-push-type: "alert"`, `apns-priority: "10"`. Silent push: `"background"`, `"5"`, `aps["content-available"] = 1`, **no** alert/sound/badge. `badge` is a number on `aps`; `notification.badge` does not exist.
- Chunk `sendEachForMulticast` at **500**; `subscribeToTopic` at **1000**; payload < **4 KB**.
- Retry only `messaging/server-unavailable`, `messaging/internal-error`, `messaging/unknown-error`, rate-limit errors.
- Trigger-produced pushes are idempotent via `notifications/{eventId}` + `ref.create()`.
- `sendMulticast`, `sendAll`, `sendToDevice` are **removed in firebase-admin 13**.
- Flutter: the background handler must be a **top-level, non-anonymous function annotated `@pragma('vm:entry-point')`** that calls `await Firebase.initializeApp()` itself — *"it runs in a separate isolate with no access to your providers."*
- The APNs `.p8` auth key must be uploaded in the Firebase console — *"Without it iOS sends succeed at FCM and never arrive; check this before debugging payloads."*

---

## 5. Flutter mandated ruleset

### 5.1 Targets

- `dart-pro`: **Dart 3.13.4, Flutter 3.47.5, flutter_lints 6.0.0, very_good_analysis 11.x**, `sdk: ^3.13.0`, `flutter: ">=3.47.0"`.
- `flutter-widgets-pro`: **Flutter 3.47.5, Dart 3.13.4, material_ui 1.3.x / cupertino_ui 1.x, go_router 18.0.x**.
- `flutter-testing-pro`: flutter_test + integration_test from the SDK, **mocktail 1.0.5, mockito 5.8.1, fake_async 1.3.3, clock 1.1.3**.

### 5.2 The Material/Cupertino package split (repeated in four skills)

> *"Flutter 3.47 decoupled Material and Cupertino into packages. New code imports `package:material_ui/material_ui.dart` and `package:cupertino_ui/cupertino_ui.dart`. `package:flutter/material.dart` still compiles but is frozen (since 3.44) and scheduled for formal deprecation… its classes are **distinct types** from the package's, so mixing the two produces 'argument type X is not the type X' errors. Migrate with `dart fix --apply --code=migrate_design_widgets`."*

`package:flutter/widgets.dart`, `/rendering.dart`, `/services.dart`, `/foundation.dart` are unchanged. **go_router 18 depends on `material_ui ^1.0.0` and `cupertino_ui ^1.0.0`** — so go_router 18 forces this migration.

### 5.3 Dart language rules (`dart-pro`)

Seven core principles: the type system is the specification (`dynamic`/`late` are admissions of defeat); model alternatives as `sealed` hierarchies, not nullable-field bags; records are for anonymous local tuples only; immutability by default; every `Future` awaited/returned/`unawaited`, every `StreamSubscription` cancelled and `StreamController` closed; errors are values at the boundary and exceptions in the middle; *"The analyzer runs before you do."*

Concrete rules:
- Language-feature floor is Dart 3.13; the skill dates each feature (primary constructors 3.13, private named parameters 3.12, dot shorthands 3.10, null-aware elements 3.8, wildcards 3.7, extension types 3.3).
- Flag every `late` that exists only to avoid `?`. `late final` set once in `initState` is acceptable.
- Never `!` where promotion is possible; a field promotes only when **private and final** — *"copy it to a local first."*
- No unguarded `as` casts; use `if (value case final String s)`.
- Never `dynamic` — use `Object?`. *"`dynamic` disables every check including typo detection."*
- Class modifiers: `sealed` for closed hierarchies, `final` for leaf types, `base` when subclasses must exist but the contract must hold, `interface` for published contracts, plain `class` only when genuinely open.
- **Switch over a `sealed` supertype with no `default`.** *"The `default` re-opens the switch and silently swallows the new subtype you add next month."*
- `const` constructors + `final` fields + `==`/`hashCode` on every value type; use `Object.hash`/`Object.hashAll`; switch to `freezed`/`equatable` past ~4 fields; never `==` on a mutable class.
- `Future.wait` rejects with the first error but still waits for all by default; `eagerError: true` rejects early; **neither cancels** — *"a `Future` in Dart is not cancellable."*
- Catch narrowly (`on FormatException catch (e)`); a bare `catch (e)` must `rethrow` or convert to a domain error **with its `StackTrace`** (`catch (e, st)`). Never `catch (_) {}`.
- `print` banned; `debugPrint` or `dart:developer`'s `log(...)`.
- Reach for `package:collection` before manual loops; `Iterable.nonNulls`, `.indexed`, `.elementAtOrNull`, `.whereType<T>()` are in `dart:core`.

### 5.4 The prescribed `analysis_options.yaml`

`dart-pro/references/style-and-lints.md` (verbatim):

```yaml
include: package:flutter_lints/flutter.yaml
# or, for a stricter house style:
# include: package:very_good_analysis/analysis_options.yaml

analyzer:
  language:
    strict-casts: true       # no implicit dynamic → T downcasts
    strict-inference: true   # no silently-inferred dynamic
    strict-raw-types: true   # no bare `List`, `Future`, `Map`
  errors:
    invalid_annotation_target: ignore   # freezed/json_serializable noise
    todo: ignore
    unawaited_futures: error            # promote a lint so CI fails on it
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "**/*.mocks.dart"
    - "build/**"

linter:
  rules:
    # correctness
    - avoid_dynamic_calls
    - avoid_slow_async_io
    - cancel_subscriptions
    - close_sinks
    - collection_methods_unrelated_type
    - unrelated_type_equality_checks
    - hash_and_equals
    - avoid_equals_and_hash_code_on_mutable_classes
    - only_throw_errors
    - throw_in_finally
    - avoid_catches_without_on_clauses
    - discarded_futures
    - unawaited_futures
    - test_types_in_equals
    - invalid_case_patterns
    - implicit_call_tearoffs

    # style / intent
    - always_declare_return_types
    - prefer_final_locals
    - prefer_final_in_for_each
    - prefer_const_constructors
    - prefer_const_constructors_in_immutables
    - prefer_const_declarations
    - prefer_const_literals_to_create_immutables
    - use_super_parameters
    - use_enums
    - unnecessary_breaks
    - unnecessary_underscores
    - sort_constructors_first
    - directives_ordering
    - avoid_positional_boolean_parameters
    - library_private_types_in_public_api
    - always_use_package_imports
    - avoid_print

    # Dart 3.13
    - use_declaring_parameters
    - unnecessary_primary_constructor_body
    - unnecessary_type_name_in_constructor
    - unnecessary_const_in_enum_constructor
    - initialize_in_field_declaration
    - empty_container_bodies
```

> *"`strict-casts` is the single highest-value switch in the file: it turns every implicit `dynamic` downcast (the entire `jsonDecode` surface) into a compile error."*

Contentious-rule guidance: leave `require_trailing_commas` **off** (the 3.7+ tall formatter handles it); `always_specify_types` **off**; `public_member_api_docs` on for packages, off for app `lib/`; pick **one** of `prefer_relative_imports` / `always_use_package_imports` (the file enables `always_use_package_imports`); generated files go in `analyzer.exclude`, not `.gitignore`.

Formatting: `dart format .` in CI with `--set-exit-if-changed`; no configuration beyond `--line-length` (default 80); *"do not argue about it."* The style is **language-versioned** from the pubspec's SDK lower bound.

Naming table (Classes `UpperCamelCase`, files `lowercase_with_underscores`, constants **`lowerCamelCase` not SCREAMING_CAPS**, private `_`, wildcard `_`). Library layout: `lib/src/…` + barrels; imports ordered `dart:` → `package:` → relative; class member order = static constants, instance fields, constructors, public methods, private methods.

`part`/`part of` exists **only for generated code**, with the string-URI form (`part of 'note.dart';`).

### 5.5 Widget layer rules (`flutter-widgets-pro`)

Seven principles: widgets are immutable configuration and Elements hold state; `build` is pure and may run at any time; constraints down / sizes up / parent sets position; every controller you create you dispose; rebuild the smallest subtree; theme once at `ThemeData`; the package split.

Hard rules:
- `const` constructors everywhere the fields allow, and `const` at every call site — *"the cheapest optimisation available."*
- **Extract into a `StatelessWidget` class, not a `Widget _buildFoo()` helper.** *"A helper returns a subtree that belongs to the caller's `Element`, so it rebuilds whenever the caller does, cannot be `const`, and gets no `RepaintBoundary` or diagnostics node of its own."*
- Keys only for identity across reorder/insert/remove: `ValueKey` (stable domain id), `ObjectKey`, `UniqueKey` (force teardown). `GlobalKey` for cross-tree access and *"never one per list item."*
- Controllers created in `initState`, disposed in `dispose`, `super.dispose()` last. React to a changed `widget.x` in `didUpdateWidget`. Controllers passed in are disposed by their creator.
- After **any** `await` in a `State` method: `if (!mounted) return;` before `setState`/`Navigator`/`ScaffoldMessenger`/`Theme.of` — and capture `BuildContext`-derived objects **before** the await.
- Never `setState` in `build`, in `dispose`, or from a layout-phase listener. One-shot post-first-frame work goes in `addPostFrameCallback` from `initState` with a `mounted` re-check.
- `Expanded` vs `Flexible`; a `ListView` inside a `Column` needs `Expanded`/`Flexible`, **not** `shrinkWrap: true` (*"which disables viewport recycling"*).
- `MediaQuery.sizeOf`/`.paddingOf`/`.viewInsetsOf`/`.textScalerOf`/`.platformBrightnessOf` over `MediaQuery.of(context)`.
- Long lists: `ListView.builder`/`.separated` or `SliverList.builder`, each item with a `ValueKey` from the model id; `itemExtent`/`prototypeItem` for uniform rows.
- **3.41+ API moves:** `scrollCacheExtent: const ScrollCacheExtent.pixels(n)` (`cacheExtent`/`cacheExtentStyle` deprecated); `findItemIndexCallback` (`findChildIndexCallback` deprecated — *"its indices counted separators"*); `ReorderableListView.onReorderItem` (`onReorder` deprecated with its manual `if (oldIndex < newIndex) newIndex -= 1` fix-up).
- Theming: `ColorScheme.fromSeed(seedColor:, brightness:)`; colour read only as a role (`surfaceContainerHigh`, `onSurfaceVariant`, `outlineVariant`); `background`/`onBackground`/`surfaceVariant` deprecated → `surface`/`onSurface`/`surfaceContainerHighest`. Type only via M3 names `display/headline/title/body/label × Large/Medium/Small`; 2018/2021 names (`headline6`, `bodyText2`, `subtitle1`, `caption`, `button`, `overline`) are **gone**.
- `.withValues(alpha: 0.5)` (`.withOpacity` deprecated); `MediaQuery.textScalerOf` + `TextScaler` (`textScaleFactor` deprecated).
- Back handling: `PopScope(canPop:, onPopInvokedWithResult: (didPop, result) {…})`. `WillPopScope` deprecated and breaks Android predictive back; `onPopInvoked` deprecated.
- Accessibility: label every interactive widget without visible text; **48×48** minimum tap target; `Semantics(headingLevel: 1)` not `header: true` (*"a no-op on iOS and Android since 3.47"*); never disable text scaling.

### 5.6 Navigation

`flutter-widgets-pro/references/navigation.md`:

- **go_router 18.0.x.** Declared once as a `GoRouter` passed to `MaterialApp.router(routerConfig: …)`.
- `MaterialApp` named routes (`routes:`, `onGenerateRoute:`, `pushNamed`) are *"the worst of both worlds… Do not add them to new code."* `Navigator.push` stays correct for non-addressable local pushes (picker sheet, crop screen).
- Constructor params documented: `routes` (required), `initialLocation`, `redirect`, `refreshListenable`, `errorBuilder`, `errorPageBuilder`, `navigatorKey`, `debugLogDiagnostics`, `observers`, `restorationScopeId`, `onException`, `onEnter`, `redirectLimit`, `routerNeglect`, `overridePlatformDefaultLocation`, `requestFocus`, `extraCodec`.
- Methods: `go`, `goNamed`, `push`, `pushNamed`, `pushReplacement`, `pushReplacementNamed`, `replace`, `replaceNamed`, `pop`, `canPop`, `namedLocation`, `refresh`, `restore` + `context` extensions. *"`go` replaces the whole stack… `push` adds one route. Use `go` for tab switches and post-login landing, `push` for drilling in."*
- **Auth gating** via a top-level `redirect` + `refreshListenable`; `null` = no redirect; `redirectLimit` (default 5) guards loops.
- **`extra` is a finding when it carries a model.** *"Pass an **id** in the path and load the object on the destination. Treat 'passes a whole model through `extra`' as a finding."* It is not URL-encoded, breaks deep links, web reloads and state restoration.
- Per-tab state: `StatefulShellRoute.indexedStack` with `StatefulShellBranch`es; `shell.goBranch(index:, initialLocation: i == shell.currentIndex)` resets the branch on re-tap; a route that must cover the tab bar sets `parentNavigatorKey: _rootKey`.
- Typed routes via `go_router_builder` (`@TypedGoRoute<T>`, `GoRouteData` + `with _$RouteName`, `dart run build_runner build --delete-conflicting-outputs`). A subclass overrides at least one of `build`/`buildPage`/`redirect`; `onExit` guards leaving (unsaved changes).
- Returning data: `await context.push<bool>('/notes/$id/edit')` ↔ `context.pop(true)`. `go` returns nothing.
- Deep links: path patterns serve Universal Links and custom schemes; *"A link that arrives before auth resolves must not bounce to the sign-in screen permanently: gate on a tri-state (`unknown`/`signedOut`/`signedIn`) and return `null` from `redirect` while unknown, showing a splash route."* `onEnter` (16.3+) for one-shot interception, `redirect` for policy.
- State restoration: `MaterialApp.restorationScopeId` + `GoRouter(restorationScopeId:)` + per-branch `restorationScopeId`.

### 5.7 Testing (`flutter-testing-pro`)

Seven principles, then rules:
- `flutter test` collects `test/**/*_test.dart` with a `void main()`; **a helper named `*_test.dart` with no tests fails the run** — name helpers `*_helpers.dart` or put them in `test/support/`.
- **Every `WidgetTester` method returns a `Future`** — a missing `await` on `tap`/`pump`/`enterText` produces a `TestAsyncUtils` assertion or a test that passes for the wrong reason.
- Prefer `await tester.pump()` + explicit `pump(duration)` per animation step over `pumpAndSettle()`. Never `pumpAndSettle` on a tree with an indeterminate progress indicator, a repeating ticker, or a `Stream.periodic`-fed `StreamBuilder` — *"this test hangs for ten minutes and then fails with a timeout, not an assertion."*
- Finders: `find.byKey(const ValueKey('submit'))` for controls the test drives; `find.text(...)` for content the user reads; `find.byType` only for one-of-a-kind widgets.
- Matchers: `findsOneWidget`/`findsNothing`/`findsNWidgets(n)`/`findsAtLeastNWidgets(n)` for widget finders; `findsOne`/`findsAny`/`findsExactly(n)`/`findsAtLeast(n)` for a generic `FinderBase`.
- Surface: `tester.view.physicalSize`, `tester.view.devicePixelRatio`, `tester.platformDispatcher.textScaleFactorTestValue` — **always** paired with `addTearDown(tester.view.reset)` / `clearAllTestValues`. `tester.binding.window` is deprecated — *"treat any `window.physicalSizeTestValue` … in a diff as a finding."*
- `await tester.runAsync(() async { … })` for genuinely async work (image decode, `rootBundle`).
- Inject `DateTime.now()` through `package:clock` (`clock.now()` in production, `withClock(Clock.fixed(...), …)` in tests).
- Debounce/throttle/retry: `fakeAsync` for plain Dart, `tester.pump(duration)` in widget tests; assert on `async.pendingTimers`.
- HTTP: `MockClient` from `package:http/testing.dart`, **not** a mocked `http.Client`. Platform channels via `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, handler)`, cleared with `null` in `addTearDown`. `SharedPreferences.setMockInitialValues({...})` in `setUp`; `SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty()` for the async API.
- **Hand-written fakes are the default**; mocktail only for call-order/argument assertions. *"Never mock a type you do not own."*
- Goldens: behind an `@Tags(['golden'])` + `dart_test.yaml` entry so `--exclude-tags golden` works; `expectLater(find.byType(MyCard), matchesGoldenFile('goldens/my_card.png'))`; re-baseline with `--update-goldens` and **never commit a re-baselined PNG without reading the diff**; generate and verify in one environment.
- `integration_test/` stays small: one `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` per entry point, a handful of flows, *"nothing that a widget test could have caught."*
- Coverage: `flutter test --coverage` → `coverage/lcov.info`, then strip `*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `firebase_options.dart`. *"Coverage that counts generated code is a number about the generator."*
- **No `retry:` in `dart_test.yaml` to paper over flakiness.** *"A flaky test is a defective test, not a defective CI runner."*
- A shared `test/support/pump_app.dart` extension is the single place that knows how a page is mounted.

### 5.8 `riverpod-pro` — framework-agnostic guidance only (we are not adopting Riverpod)

Everything provider-specific is out of scope, but these carry over verbatim to a `flutter_bloc` app:

1. **Feature-first layout with one-way dependency arrows** (`riverpod-pro/references/architecture.md`):

| Layer | Contains | May import |
|---|---|---|
| `data` | repositories, DTOs, wire mapping | `core`, packages |
| `application` | state holders, derived state | `data`, `core` |
| `presentation` | widgets | `application`, `core`, Flutter |

   *"`data` never imports `presentation`. `application` never imports `package:material_ui/material_ui.dart`."*
2. **The repository boundary is an `abstract interface class`** — state holders never call HTTP/Firestore/`SharedPreferences` directly.
3. **DI by injecting an explicitly-unimplemented dependency at the composition root**, so *"a test that forgets to fake the dependency fails loudly instead of hitting the network"* and `main()` is the only file naming concrete implementations. Real defaults only for pure dependencies (clock, UUID, formatter).
4. **`BuildContext` never crosses into `application`.** *"Passing `context` into a notifier method is the same bug as storing it in a field."*
5. **Navigation is a widget concern.** *"React to state … in the widget and call `Navigator`/`GoRouter` there. If the router itself must be reactive, expose the *state* it needs … and let the router watch it — the router object may live in a `Provider`, but it must never be pushed to from a notifier."*
6. **Platform channels, permissions, notifications, file pickers go behind a service interface in `data`.**
7. **Side effects (dialogs, snackbars, navigation, analytics) belong in a listen-style callback, never in `build`.**
8. **State is replaced, never mutated** — `state.add(x)` mutates the same object, `==` is true, no rebuild. (Directly applicable to `Equatable`-based bloc states.)
9. **Every async gap needs a liveness check** before assigning state.
10. **Sealed `AsyncValue`-style state switched exhaustively**, not `when(data:, error:, loading:)` — *"`when` compiles even when a case is wrong."*
11. **Observers are the single place for logging state transitions and reporting errors to Crashlytics.**
12. One Riverpod-specific item that still matters if anyone reaches for it: Riverpod 3 auto-retries failing providers (up to 10 attempts, 200 ms → 6.4 s) and *"For a form submission that must fail fast, pass `retry: (count, error) => null`."*

---

## 6. AdMob mandated ruleset

Source: `ios-admob-ads-skill/` — SKILL.md, 10 references, 9 template files.

### 6.1 The framing

> *"Two failures are permanent and one is not: 1. **Account suspension for *how* ads are placed**… Google suspends for implementation, not content. 2. **Uninstalls and one-star reviews.** They don't come back. 3. Low fill / low revenue — fixable next week by editing Remote Config."*
>
> *"When a trade-off between revenue and (1) or (2) comes up, choose (1)/(2) and say so."*

### 6.2 The ten hard rules (verbatim summaries)

1. **Debug builds never request real ad units.** Under `#if DEBUG` every format resolves to Google's official test unit, ignoring Remote Config and Info.plist.
2. **All timing rules live in one pure function, `AdGate`,** which never touches the SDK. The SDK is asked only *after* the gate says yes.
3. **Two separate switches, in order:** global `ads.enabled`, then the user's entitlement. *"Never merge them — merging is how a paying subscriber sees an ad, and that's the ad that generates refunds."*
4. **Master switch off ⇒ SDK not started and consent not requested.** Ship with `ads.enabled = false` and turn on remotely, format by format.
5. **Interstitials only between content pages**: never at launch, never at exit, never after every action (max 1 per 2 completions), never right after another full-screen ad.
6. **No ads on "work" screens** (camera, editor, reader, player, form, AI result).
7. **Rewarded: the client never credits the reward.** SSV only.
8. **Native ads are drawn inside the SDK's `NativeAdView`** with registered asset views.
9. **Never pass user content or PII to ad requests.**
10. **Privacy labels describe the binary, not the switch.**

### 6.3 Ad formats covered

All six, with per-format notes (`references/formats.md`, API names are **GMA SDK 12.x Swift** — `MobileAds`, `InterstitialAd`, `AppOpenAd`, `RewardedAd`, `Request`, `FullScreenContentDelegate`; SDK 11 uses `GAD`-prefixed names):

| Format | Enum case | Default `enabled` | Placement |
|---|---|---|---|
| App Open | `appOpen` | true | Returning to foreground after ≥45 s in background |
| Interstitial | `interstitial` | true | Transition *out of* a done moment back to a browse screen |
| Rewarded | `rewarded` | true | User-initiated, where a limit is hit |
| Rewarded interstitial | `rewardedInterstitial` | (off unless asked) | Only with an intro screen stating the reward and a clear skip |
| Native | `native` | true | Inside browse lists; below a "done" result screen |
| Banner | `banner` | **false** | *"Nowhere by default"* |

Common full-screen rules: preload one ahead per format and reload in `adDidDismissFullScreenContent`; **never load on the trigger** (*"late pop-in is a policy violation"*); ads expire — App Open after **4 h**, interstitial/rewarded ~1 h is a safe refresh horizon, store `loadedAt` and discard stale ads; retry failed loads with backoff (30s, 60s, 120s… cap 10 min); every request carries `npa=1`; set `paidEventHandler` right after load; present from the topmost view controller else `notReady`. Delegate order: `adWillPresentFullScreenContent` → record shown; `adDidDismissFullScreenContent` → record dismissed + preload; `didFailToPresent` → preload + report failed.

App Open extras: trigger on `.active` with **measured** background time; never on cold launch of the first sessions; on later cold launches only if already loaded (don't block a splash); suppress when a system sheet (share, document picker, camera) or paywall is on screen, and set a suppression flag before your own external flows (Safari login, Sign in with Apple, App Store page).

Interstitial extras: call `recordCompletion()` on **every** trigger regardless of outcome; show *after* the user's result is safely persisted and visible.

Rewarded extras: only from an explicit tap on a button that says what they'll get; set `ServerSideVerificationOptions` on the **loaded ad right before presenting** — *"it identifies the viewer, not the request."*

Native extras: request `.native` with `NativeAdViewAdOptions` (AdChoices corner) + `NativeAdMediaAdLoaderOptions`; the console unit must be **Native advanced**, not a native banner — *"mismatched unit types never fill."*

Banner extras (if enabled): anchored adaptive banner sized from the container width, one request per visible placement, console refresh interval ≥30 s, never overlapping controls, never in scroll content that would push/obscure the main action.

### 6.4 The frequency gate — algorithm, precisely

`templates/AdsCore/AdGate.swift`. The gate is **pure**: no SDK, no `Date()`, no `UserDefaults` — time and calendar are passed in.

**Types:**

```swift
enum Decision { case allow; case refuse(Refusal) }

enum Refusal: String {
  case masterSwitchOff, notEntitledToAds, formatDisabled, placementDisabled,
       dailyCap, tooSoonSinceSameFormat, fullScreenCooldown,
       tooFewCompletionsSinceLast, tooFewLifetimeCompletions,
       sessionTooYoung, earlySession, backgroundTooShort
}

struct Context { var ledger: AdLedger; var adsEntitled: Bool; var now: Date; var calendar: Calendar }
```

**`common(config, context)` — always first, in this order:**
1. `config.enabled == false` → `.masterSwitchOff`
2. `context.adsEntitled == false` → `.notEntitledToAds`

(Note: `adsEntitled == true` means "this user should see ads"; `AdsConfig` calls the user-plan field `adsEnabled`.)

**`appOpen(config, context, secondsInBackground)`:**
1. `common` → refuse
2. `!rules.enabled` → `.formatDisabled`
3. `ledger.sessionCount > rules.skipFirstSessions` else `.earlySession` *(strictly greater — with `skipFirstSessions = 3`, the 4th session is the first eligible)*
4. `secondsInBackground >= rules.minimumBackgroundSeconds` else `.backgroundTooShort`
5. `fullScreenCooldown`: `now - ledger.lastFullScreenDismissedAt < config.fullScreenCooldownSeconds` → `.fullScreenCooldown`
6. `spacing(.appOpen)`: `now - ledger.lastShownAt[.appOpen] < rules.minimumSecondsBetween` → `.tooSoonSinceSameFormat`
7. `cap(.appOpen)`: `ledger.shownToday(.appOpen, on: now, calendar:) >= rules.maxPerDay` → `.dailyCap`
8. `.allow`

**`interstitial(config, context)`** — *"Call from a 'done' moment **after** `ledger.recordCompletion()`."*
1. `common` → refuse
2. `!rules.enabled` → `.formatDisabled`
3. `ledger.lifetimeCompletions >= rules.minimumLifetimeCompletions` else `.tooFewLifetimeCompletions`
4. `let completionsBetween = max(2, rules.minimumCompletionsBetween)` — **the AdMob policy floor is hard-coded in code, not config.** If `ledger.lastShownAt[.interstitial] != nil` **and** `ledger.completionsSinceInterstitial < completionsBetween` → `.tooFewCompletionsSinceLast`. *(The first-ever interstitial is not blocked by this rule; the lifetime-completions rule covers it.)*
5. `ledger.sessionStartedAt` exists **and** `now - sessionStartedAt >= rules.minimumSessionSeconds` else `.sessionTooYoung`
6. `fullScreenCooldown` → `.fullScreenCooldown`
7. `spacing(.interstitial, rules.minimumSecondsBetween)` → `.tooSoonSinceSameFormat`
8. `cap(.interstitial, rules.maxPerDay)` → `.dailyCap`
9. `.allow`

**`rewarded(config, context)`** — deliberately the shortest chain (user-initiated):
1. `common` → refuse
2. `!config.rewarded.enabled` → `.formatDisabled`
3. `cap(.rewarded, config.rewarded.maxPerDay)` → `.dailyCap`
4. `.allow`

No cooldown, no spacing, no session rules for rewarded.

**`native(placement:config:adsEntitled:)` / `banner(...)`** (no ledger, no time):
1. `!config.enabled` → `.masterSwitchOff`
2. `!adsEntitled` → `.notEntitledToAds`
3. `!config.<format>.enabled` → `.formatDisabled`
4. `!config.<format>.placements.contains(placement)` → `.placementDisabled`
5. `.allow`

**Native row placement algorithm:**

```swift
static func nativeRows(itemCount: Int, config: AdsConfig.Native) -> [Int] {
  let first = max(1, config.firstRow) - 1       // 1-based display row → item index
  let every = max(1, config.everyRows)
  guard config.maxPerScreen > 0, first >= 0 else { return [] }
  var rows: [Int] = []
  var index = first
  while index < itemCount, rows.count < config.maxPerScreen {
    rows.append(index); index += every
  }
  return rows
}
```

With defaults (`firstRow: 6, everyRows: 10, maxPerScreen: 3`) and a 40-item list: ads inserted before item indices `[5, 15, 25]`. The `index < itemCount` condition means *"An ad is only placed with at least one content item after it, so short lists get none and an ad never ends a list."*

`nativeChunks<T>(items:config:)` is **derived from** `nativeRows` by cutting at those indices — *"a test asserts they agree, so the third ad can never be in different places in list vs grid."*

**The ledger** (`AdLedger`, a `Codable` value type, JSON in `UserDefaults`):

```swift
var sessionCount = 0
var sessionStartedAt: Date?
var lifetimeCompletions = 0
var completionsSinceInterstitial = 0
var lastShownAt: [AdFormat: Date] = [:]
var lastFullScreenDismissedAt: Date?
var dayKey = ""                      // "yyyy-MM-dd" from the injected calendar
var shownToday: [AdFormat: Int] = [:]
```

Day rollover via `normalized(for:calendar:)` — if the computed `dayKey` differs, `shownToday` is emptied. Mutations: `recordSessionStart(at:)` (increments `sessionCount`, sets `sessionStartedAt`), `recordCompletion()` (increments both counters), `recordShown(_:at:calendar:)` (normalizes, increments `shownToday`, sets `lastShownAt`, **and resets `completionsSinceInterstitial` to 0 when the format is `.interstitial`**), `recordFullScreenDismissed(at:)`.

Gate/ledger contract from `references/architecture.md`:
- *"If the gate says allow but no ad is loaded, **show nothing** and record `noFill`/`notReady`. Never wait for a load on the trigger."*
- *"Record `shown` only when the SDK reports the ad actually presented (`adWillPresentFullScreenContent`), and `dismissed` on dismissal — the cooldown starts there."*
- Persist the ledger after every mutation.

### 6.5 Remote Config keys

`references/config-schema.md` + `templates/ads_config.defaults.json`. One Remote Config parameter per domain (`ads_config`), a JSON string; a domain that fails to parse keeps **its own** defaults without affecting others; defaults ship in the bundle via `setDefaults`.

> *"**Defaults are always the safe side**: ads off, wide spacing, low caps. A build that can't reach Remote Config must behave like the mildest build, not the most aggressive."*

| Key | Default | Meaning |
|---|---|---|
| `enabled` | **false** | Master switch. Off ⇒ SDK not started, consent not requested |
| `fullScreenCooldownSeconds` | 30 | No full-screen ad of any format within N seconds of the last full-screen dismissal |
| `appOpen.enabled` | true | |
| `appOpen.minimumBackgroundSeconds` | 45 | |
| `appOpen.minimumSecondsBetween` | 300 | |
| `appOpen.maxPerDay` | 4 | |
| `appOpen.skipFirstSessions` | 3 | *"First sessions are when people decide whether to keep the app"* |
| `interstitial.enabled` | true | |
| `interstitial.minimumSecondsBetween` | 180 | |
| `interstitial.minimumCompletionsBetween` | 2 | *"AdMob: max 1 interstitial per 2 actions. Clamped to ≥2 in code"* |
| `interstitial.maxPerDay` | 6 | |
| `interstitial.minimumSessionSeconds` | 60 | |
| `interstitial.minimumLifetimeCompletions` | 3 | |
| `native.enabled` | true | |
| `native.placements` | `[]` | Placement **names** allowed to render |
| `native.firstRow` | 6 | 1-based display row of the first ad |
| `native.everyRows` | 10 | Content rows between ads |
| `native.maxPerScreen` | 3 | |
| `banner.enabled` | **false** | |
| `banner.placements` | `[]` | |
| `rewarded.enabled` | true | |
| `rewarded.maxPerDay` | 3 | |
| `rewarded.grantAmount` | 5 | *"Informational for UI copy only; the **server** clamps the real grant"* |
| `unitIDs` | `{}` | Per-format override: `appOpen`, `interstitial`, `rewarded`, `rewardedInterstitial`, `native`, `banner` |

**Ad unit ID resolution order:** `unitIDs` (Remote Config) → `Info.plist` `GADUnitID_<format>` → compiled constant. Each step skipped when empty/whitespace, *"so a half-filled block can never leave a format with no ID."* Unknown keys are **kept**, not rejected, so an ID can be pre-staged before the build that uses it ships. **Debug ignores all three** and returns Google's test units:

```
appOpen              ca-app-pub-3940256099942544/5575463023
interstitial         ca-app-pub-3940256099942544/4411468910
rewarded             ca-app-pub-3940256099942544/1712485313
rewardedInterstitial ca-app-pub-3940256099942544/6978759866
native               ca-app-pub-3940256099942544/3986624511
banner               ca-app-pub-3940256099942544/2435281174
test app ID          ca-app-pub-3940256099942544~1458002511
```

Schema evolution: renaming a key is **breaking** (running builds fall back to the default) — add the new key, keep reading the old for a release or two, then drop. Tune with **console conditions** (country, app version, % of users), not builds. Lower `minimumFetchInterval` via a condition while tuning (Release default 12 h). *"Turn formats on one at a time, and watch uninstall rate + refusal reasons for a week each."*

### 6.6 UMP consent flow and its relationship to ATT

`references/consent-privacy.md`. **Default stance: non-personalized, no ATT.**

- Do not request ATT. Serve non-personalized ads only (`npa=1` on **every** request).
- *"The SDK still serves ads without IDFA; eCPM is lower, but the App Privacy label has no 'Data Used to Track You' section, which is a real selling point for apps handling private data."*
- `NSPrivacyTracking = false` in the privacy manifest.
- Switching to personalized ads is **a package change, not a flag**: request ATT (with `NSUserTrackingUsageDescription`) before loading ads, set `NSPrivacyTracking = true`, list `NSPrivacyTrackingDomains`, update the nutrition label to Tracking = Yes, drop `npa`. *"Doing these piecemeal is how the label says one thing and the app does another."*

**UMP order at launch — only if `ads.enabled` is true:**
1. `ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())`
2. `ConsentForm.loadAndPresentIfRequired(from: rootVC)`
3. If `ConsentInformation.shared.canRequestAds` → `MobileAds.shared.start()` then preload
4. **Also check `canRequestAds` right after step 1** (returning users) so ads aren't delayed by the form.

Settings must have a "Privacy options" row when `ConsentInformation.shared.privacyOptionsRequirementStatus == .required`, calling `ConsentForm.presentPrivacyOptionsForm(from:)`.

Debug: `RequestParameters.debugSettings` with `geography = .EEA` + the test device hash; `ConsentInformation.shared.reset()` to re-test. *"Never ship debug settings."* The GDPR message must be published in the AdMob console (Privacy & messaging) — *"the SDK shows nothing without a published message."*

Info.plist: `GADApplicationIdentifier`, `SKAdNetworkItems` (Google's current list), optional `GADUnitID_<format>` keys, **no `NSUserTrackingUsageDescription`** under the default stance.

App Store Connect — declare by **binary capability**, not Remote Config state: tick Third-Party Advertising; declare the GMA SDK data types (Device ID, Advertising Data, Product Interaction, Crash Data, Performance Data, Coarse Location from IP) as **Linked: No, Tracking: No**; remove any "no ads"/"completely free" claim; GMA SDK ≥ 11.2 ships its own privacy manifest and mediation adapters must too.

*"The only identifier sent is the auth uid in SSV `userIdentifier`, and only for rewarded — it's your own opaque ID, not an email or phone."*

### 6.7 Native ad rendering rules

`references/native-ads.md`:

- A native ad **must** be rendered inside `NativeAdView` with each asset view registered (`headlineView`, `bodyView`, `callToActionView`, `iconView`, `mediaView`, …) and `nativeAd` assigned **last**. *"The SDK counts impressions and clicks by observing that view. A custom SwiftUI card built from the strings earns nothing and shows ad assets outside their container."*
- Target split to keep features SDK-free: DesignSystem holds `NativeAdSlot(placement:slot:)` + an `EnvironmentValues.nativeAdRenderer`; AdsUI (app target only) holds `NativeAdsHost`, `NativeAdPool`, `NativeAdCardView`. When no renderer is in the environment (tests, previews, paid users, ads disabled) the slot renders `EmptyView`, zero height — *"That's not a stub — it's exactly what a free user sees on a no-fill day."*
- **The pool: one ad per `(placement, slotIndex)`.** *"Not a queue. A `NativeAd` may appear in exactly one view, so the second ad on a screen is a second request."* Both key components are stable for the screen's lifetime, so scrolling away and back shows the **same** ad and cell reuse never triggers a new request. Requests per session ≈ visible slots — *"which keeps the request/impression ratio healthy."*
- Keep an ad at most **55 min** (Google: don't cache over an hour), then replace on next display. On no-fill, back off **60 s** for that key. Clear the pool when the entitlement changes to ad-free.
- The card: full-width **between** content chunks, never disguised as a content row; a visible "Ad" badge inside the layout with the top-right corner left clear for AdChoices; clamp media aspect ratio to **1.0–1.91** (*"a tall creative would push content off screen"*); hide `mediaView` entirely when no aspect ratio is reported (*"an empty media view is a grey rectangle"*); CTA as a **non-interactive** label inside the registered `callToActionView` (`isUserInteractionEnabled = false`) — the SDK handles the click; support Dynamic Type and dark mode.

### 6.8 Rewarded SSV — end to end, including the Firebase Function

`references/rewarded-ssv.md` + `templates/server/adReward.ts`.

> *"**The client never credits a reward.** An app that accepts 'I just watched an ad, give me more' accepts it from anyone."*

**Flow:**
1. User taps "Watch an ad for N more …". `AdGate.rewarded` (master, entitlement, enabled, daily cap).
2. Right before `present`, set on the loaded ad: `serverSideVerificationOptions = { userIdentifier: <auth uid>, customRewardString: <optional context> }`.
3. `userDidEarnReward` fires → **only** show "Reward on its way…".
4. Google sends `GET <callback URL>?ad_network=…&ad_unit=…&custom_data=…&key_id=…&reward_amount=…&reward_item=…&timestamp=…&transaction_id=…&user_id=…&signature=…`
5. Server verifies and grants.
6. App, after dismissal, **re-reads the quota with backoff (1s, 2s, 4s, 8s)** — *"Google's callback usually lands after the ad closes"* — or listens to the document.

**Server side (`adReward.ts`), a Cloud Functions v2 `onRequest`:**
- Constants: `KEYS_URL = "https://www.gstatic.com/admob/reward/verifier-keys.json"`, `KEY_CACHE_MS = 24h`, `MAX_GRANT = 5`, `TX_RETENTION_DAYS = 30`.
- `splitSigned(rawQuery)` cuts the raw query at the literal `"&signature="` marker. **Critical rule:** *"cut as a string, never parsed and re-encoded, because re-encoding (e.g. `%2F` → `/`) changes the bytes Google signed."* The raw query comes from `req.originalUrl`, not `req.query`.
- `verifySignature`: URL-safe base64 → standard base64 (`-`→`+`, `_`→`/`) + padding, then `crypto.verify("sha256", message, { key, dsaEncoding: "der" }, sig)` — ECDSA P-256 / SHA-256, **DER-encoded**.
- Key cache: fetch once per 24 h; **on an unknown `key_id`, refetch once** (key rotation).
- `if (!rawQuery) { res.status(200).send("ok"); return; }` — *"AdMob console 'Verify URL' sends a request with no parameters; answer 200 so it can save."*
- Status codes are part of the contract:
  - no/unparseable query or **missing `user_id`** → **400**, grant nothing
  - keys unavailable → **500** *"so Google retries. Returning 200 here would silently swallow the reward."*
  - invalid signature → **403** (`logger.warn` with the transaction id)
  - success or already-processed → **200**
  - grant transaction failure → **500**
- Amount clamp: `Math.max(0, Math.min(MAX_GRANT, Math.floor(payload.rewardAmount || 0)))` — *"Clamp the amount server-side regardless of what the console says."*
- **One Firestore transaction** consumes `adRewards/{transaction_id}` and applies the grant: read the tx doc; if it exists return `false` (already processed, still 200); else `applyGrant(tx, uid, amount, payload)` then `tx.create(txRef, { uid, amount, adUnit, at, expiresAt })` with `expiresAt` = now + 30 days for a Firestore TTL policy.
- `applyGrant` (the app-specific part): raise the ceiling on the **current quota period document**, `users/{uid}/quota/{period}` with `rewardBonus: bonus + amount`, merged. Semantics: *"Store the grant on the current quota period document so it expires with the period (new day ⇒ gone) — no cleanup job needed"*; *"Grant **raises the ceiling**, it doesn't lower usage: 3/5 used + reward 2 ⇒ 3/7, not 1/5."*
- `onRequest({ region: "us-central1", cors: false })` in the template, and the function is **public on purpose** — *"Google has no Firebase credentials. The signature is the auth."*

**Console setup (cannot be done from code):** enable Server-side verification on the rewarded unit with the deployed function URL; set reward amount/item in the unit settings; the callback must be public. *"Without SSV enabled, nothing gets credited — that's the correct failure mode."*

**Required server tests** (`templates/server/adReward.test.mts`, run with `node --experimental-strip-types`): valid signature with `%2F` in `custom_data` verifies; tampered `reward_amount` fails; same `transaction_id` twice grants once; key-fetch failure returns 500; missing `user_id` returns 400 and grants nothing.

### 6.9 Every AdMob policy rule the skill calls out

From `references/policy-rules.md`, tagged **[AdMob]** / **[Apple]** / **[Ours]**.

**Timing [AdMob]:**
| Rule | Enforced by |
|---|---|
| No interstitial at app launch or app exit; use App Open for launch | Placement table; `AdGate.interstitial` only called from done moments |
| No interstitial after every action; max 1 per 2 completions | `minimumCompletionsBetween` (default 2, **never below 2**) |
| No interstitial right after one the user just closed | `fullScreenCooldownSeconds` + `interstitial.minimumSecondsBetween` |
| Don't place ads where they block main content or navigation | Work-screen ban |
| Preload, so ads don't pop in late over freshly shown content | Live client preloads after each show |

**Traffic [AdMob] — "the fastest way to lose the account":**
- Never load real units in Debug; also register test device IDs for TestFlight/Release testing on your own phone (`MobileAds.shared.requestConfiguration.testDeviceIdentifiers`).
- Never click your own live ads (tell QA and the team).
- Never incentivize clicks ("tap the ad to continue") — *"Rewarded rewards *watching*, not clicking."*
- Request/impression ratio matters — *"Requesting ads you never show (e.g., re-requesting a native ad every time a cell is reused) looks like a broken or abusive integration."*

**Content and data [AdMob]:**
- No PII, no user content (document text, file names, tags, search terms) in targeting/keywords/content URL.
- No personalization on sensitive categories; simplest compliant stance is `npa=1` + no ATT.
- Native ads must be clearly labeled ("Ad"/"Quảng cáo") and must not mimic app content rows.

**Apple:**
- Declare Third-Party Advertising + data types if the SDK is in the binary, even if ads are remotely disabled.
- No "no ads"/"completely free" claim in the App Store description once the SDK ships.
- ATT prompt only if you actually track; `NSUserTrackingUsageDescription` must exist and ads must wait for the answer.
- No ads in contexts reviewers consider child-directed unless set up for it (Made for Kids requires certified networks + no personalization). **[Apple][AdMob]**

**Retention [Ours]:** App Open ≥45 s background and not during the first sessions (*"switching away to copy a phone number gets punished with a full-screen ad — that alone makes people say 'this app is full of ads'"*); banner off by default (*"the most seen and most hated format, and it steals space from the most important button"*); rewarded is the only opt-in format and the only one that gives something back — *"Invest there first."*

**Placement anti-patterns to reject in review:** interstitial on tab switch / back button / opening a detail screen / app launch; interstitial shown *before* the result of the user's action (*"holding their work hostage"*); native ad styled like a content row; rewarded that credits locally or rewards clicks; **any ad on a screen showing the user's own private content**.

**Launch/audit checklist order:** account risk → Apple rejection risk → retention → revenue → operability (23 checkboxes, reproduced in §6.11 of the source file).

### 6.10 Measurement

`references/analytics.md`: the AdMob console *"cannot see a request the app decided not to make — and that's the number that separates 'this market has no fill' from 'our thresholds are too tight'."* Two streams:

| Record | Source |
|---|---|
| `AdImpression` — format, placement, `valueMicros`, currency, precision, ad source | `paidEventHandler` on every loaded ad, all formats |
| `AdEvent` — `filled`, `noFill`, `notReady`, `shown`, `dismissed`, `rewardEarned`, **`refused(reason)`** | `AdGate.Refusal` from the lifecycle + load/present results |

Nothing identifies the user. **Start with unified log only** (`Logger(subsystem:category:"ads")`) — *"Sending it to an analytics backend means collecting behavioral data from every user; that's a privacy-label and privacy-policy decision for the owner, not a code decision."* Keep the sink behind one file.

Tuning heuristics: refusals dominated by one reason → loosen that threshold for a % of users via a console condition; few refusals but many `noFill` → fill issue, thresholds won't help; impressions fine but uninstalls up → tighten App Open first, then interstitial; *"Never judge a change in less than a week of data."*

### 6.11 What is iOS/Swift-specific and needs a Flutter equivalent

| Piece | Status for a Flutter rewrite |
|---|---|
| `AdGate.swift`, `AdLedger.swift`, `AdsConfig.swift`, `AdUnitIDs.swift`, `AdEvent.swift` | **Pure logic, portable 1:1 to Dart.** No SDK import. The gate's check order, refusal enum, thresholds, day-rollover and `nativeRows`/`nativeChunks` algorithms translate directly. `templates/Tests/AdGateTests.swift` (Swift Testing) → `test/ads/ad_gate_test.dart`. |
| `AdsLiveClient.swift` (GMA SDK 12.x Swift names: `MobileAds`, `InterstitialAd`, `AppOpenAd`, `RewardedAd`, `Request`, `FullScreenContentDelegate`, `paidEventHandler`, `ServerSideVerificationOptions`) | **iOS-only. Needs a full Flutter rewrite.** ⚠️ NOT IN SKILLS: the Flutter equivalent is the `google_mobile_ads` plugin (`MobileAds.instance.initialize()`, `InterstitialAd.load`, `AppOpenAd.load`, `RewardedAd.load`, `AdRequest`, `FullScreenContentCallback`, `OnPaidEventCallback`, `ServerSideVerificationOptions`). The skill does not name it. |
| UMP flow (`ConsentInformation.shared`, `ConsentForm.loadAndPresentIfRequired`, `presentPrivacyOptionsForm`, `RequestParameters.debugSettings`) | **iOS-only API surface.** ⚠️ NOT IN SKILLS: Flutter exposes UMP through the same `google_mobile_ads` plugin (`ConsentInformation.instance`, `ConsentForm.loadAndShowConsentFormIfRequired`, `ConsentDebugSettings`). The *ordering rules* (steps 1–4, only if `ads.enabled`) port unchanged. |
| ATT stance (no ATT, `npa=1`, `NSPrivacyTracking=false`) | Policy is platform-neutral; the manifest keys are iOS. ⚠️ NOT IN SKILLS: Android has no ATT — the equivalent Android surface is the advertising ID permission and the Play Data safety form, which the skill never covers because it is iOS-only. |
| `NativeAdView` + registered asset views, `NativeAdCardView` as `UIViewRepresentable`, DesignSystem/AdsUI target split | **iOS-only implementation; the *rules* port.** ⚠️ NOT IN SKILLS: in Flutter this is `NativeAd` with a `factoryId` and a platform-side `NativeAdFactory` registered in `AppDelegate.swift` / `MainActivity.kt`, rendered via `AdWidget`. The "one ad per (placement, slot)", 55-min cache, 60-s no-fill backoff, aspect-ratio clamp 1.0–1.91, "Ad" badge, non-interactive CTA rules all carry over. The target-split rationale (keep features SDK-free) maps to a Dart package boundary. |
| App Open trigger on `scenePhase == .active` / `sceneWillEnterForeground`, measuring background time on `.background` | ⚠️ NOT IN SKILLS: Flutter equivalent is `AppLifecycleListener` or `WidgetsBindingObserver.didChangeAppLifecycleState` recording a timestamp on `paused`/`hidden`. The *rule* (measure it yourself, ≥45 s) is unchanged. |
| `Info.plist` `GADApplicationIdentifier`, `SKAdNetworkItems`, `GADUnitID_<format>`; App Store Connect privacy labels; GMA privacy manifest | **iOS-only, still required** for the iOS half of the Flutter app, plus an Android `AndroidManifest.xml` `com.google.android.gms.ads.APPLICATION_ID` meta-data ⚠️ NOT IN SKILLS. The Info.plist tier of `AdUnitIDs.resolve` needs an Android sibling ⚠️ NOT IN SKILLS. |
| `#if DEBUG` test-unit resolution | Dart equivalent is `kDebugMode`. **The rule is absolute and must survive the port**, with Google's *Android* test unit IDs added ⚠️ NOT IN SKILLS (the skill lists only the iOS ones). |
| TCA `@DependencyClient` / `DependencyKey` wiring, `AdsLiveController` `MainActor` isolation | Architecture-specific. The SKILL explicitly says *"the core is plain Swift structs + a pure enum, so it works with TCA (any version), MVVM or plain UIKit. Match the project's existing dependency style rather than introducing a new one."* → for this project: an `AdsClient` abstract interface in `data`, injected at the composition root, with a Bloc/Cubit calling `AdGate` before `AdsClient`. |
| `AdAnalytics.log` using `OSLog` `Logger` | ⚠️ NOT IN SKILLS: Dart equivalent is `dart:developer`'s `log(..., name: 'ads')` (and `dart-pro` bans `print`). |
| `adReward.ts` (Firebase Function) | **Already server-side TypeScript — portable as-is**, subject to the region conflict noted in §7. |
| Remote Config (`ads_config` JSON string, `setDefaults`, `minimumFetchInterval`) | Platform-neutral concept; ⚠️ NOT IN SKILLS: needs the `firebase_remote_config` package, which is **absent from `flutter-firebase-contract`'s version matrix**. |

---

## 7. Conflicts

### 7.1 Conflicts *within* the skill bundle

| # | Conflict | Positions | Pragmatic reconciliation |
|---|---|---|---|
| C1 | **Region of the AdMob SSV function** | Every Firebase skill mandates `region: "asia-southeast1"` set once in `setGlobalOptions` (`firebase-functions-pro/references/runtime-options.md`). `ios-admob-ads-skill/templates/server/adReward.ts` hard-codes `onRequest({ region: "us-central1", cors: false })`. | Change the template to `asia-southeast1` (or simply drop the per-function `region` and let `setGlobalOptions` apply). The SSV callback URL is registered in the AdMob console, so the region only has to be stable — but co-locating it with Firestore matters because it does a transaction. Re-register the URL in the console after moving. |
| C2 | **`adReward.ts` is an `onRequest` with no auth/App Check**, which `firebase-security-pro` otherwise forbids | `firebase-security-pro/SKILL.md`: *"`onRequest` handlers that need identity verify `Authorization: Bearer <idToken>`… Never accept a uid from the body or query string."* `rewarded-ssv.md`: *"The callback function must be public (no Firebase auth — Google has none). Security is the signature check."* | Not a real conflict — it is the documented webhook exception (same shape as the RevenueCat webhook in `firebase-functions-pro`'s project layout). Keep it public, keep the ECDSA verification as the only auth, set `maxInstances` and never log the query string. |
| C3 | **Does the callable request carry a `client` block?** | `firebase-ios-contract/references/versioning.md` mandates `ClientInfo { appVersion, build, platform }` on **every** request, validated inside the shared `parse()`. `flutter-firebase-contract/SKILL.md`'s canonical `CreateNoteRequest` has **no** `client` field, and `shared-types.md`'s `CreateNoteInput` does include `client: ClientInfo`. | Adopt the `client` block — the min-version gate is the only mechanism the skills give for forcing an app update, and `Remote Config for the force-update gate` is explicitly rejected. Extend `ClientInfo.platform` from `z.enum(["ios"])` to `z.enum(["ios","android"])` (⚠️ NOT IN SKILLS — the skills are iOS-only here). Put it in a Dart `ClientInfo` mixin included by every request's `toJson()`. |
| C4 | **`network` failure case** | `firebase-ios-contract/references/error-mapping.md` has a first-class `.network` kind fed by `NSURLErrorDomain`. `flutter-firebase-contract/references/error-mapping.md` says the Flutter plugin folds transport errors into `unavailable`/`deadline-exceeded` and *"Do not write a Dart branch that waits for a separate network error domain."* | The Flutter doc wins for the Dart half — it is explicitly a correction. Keep `NetworkFailure` in the sealed hierarchy only for errors from a connectivity pre-flight that never reach the plugin, exactly as the Dart doc says. |
| C5 | **Riverpod is assumed by `flutter-firebase-contract`** | Its canonical example, `references/riverpod-integration.md`, and several cross-references assume `ProviderScope`/`StreamProvider`/`AsyncNotifier`. The brief says Riverpod is not being adopted. | Keep the *layering* and the *repository interface* (both framework-agnostic and restated in `riverpod-pro/references/architecture.md`), and substitute Bloc/Cubit for the notifier and `RepositoryProvider`/`BlocProvider` for the provider overrides. The rules that matter — Firebase types never above `data`, one fake at the repository interface, `AsyncValue.guard`-style error capture → emit a failure state — all survive the swap. |
| C6 | **`firebase-testing-pro` targets iOS end-to-end** (`references/ios-against-emulator.md`, XCUITest) | vs `flutter-firebase-contract/references/emulators-and-testing.md` + `flutter-testing-pro`'s `integration_test`. | Use the Flutter path for the client; keep `firebase-testing-pro` for everything server-side (vitest, rules tests, seed directory, CI). One `seed/` export feeds both. |
| C7 | **Dart 3.13 `class const Tag(final String label, …)` primary constructors** in `dart-pro`'s canonical example | Requires Dart 3.13 language version; anything on a lower SDK constraint silently gets the old parse. | Pin `sdk: ^3.13.0` in `pubspec.yaml` (which `flutter-firebase-contract/references/setup.md` also requires) or avoid primary constructors. The formatter style is versioned off the same constraint. |

### 7.2 Conflicts with the existing backend (JavaScript + Express `onRequest` REST)

| # | Skill position | Existing app | Reconciliation |
|---|---|---|---|
| B1 | **TypeScript, `strict: true`, NodeNext, ES2022, zod** (`firebase-functions-pro`, all references) | Plain JavaScript | No middle ground that preserves the contract: the whole zod-schema-as-source-of-truth model, `z.infer` types, the `parse<T>` helper and the contract snapshot tests need TS. Migrate `functions/` to TS. If a staged migration is needed, `allowJs: true` + per-file conversion, converting **schema and handler files first** since they carry the contract. |
| B2 | **`onCall` is the default transport; `onRequest` only for webhooks** (`callable.md`, verbatim) | Express `onRequest` REST for everything | This is the single biggest conflict. What callables give you for free and REST does not: automatic ID-token attachment, automatic App Check token attachment, `enforceAppCheck` as a one-line option, automatic CORS, and — most importantly — the `HttpsError` → `FunctionsErrorCode` → sealed `ApiFailure` mapping that sections 1.6 and 4.4 are built on. **Recommendation: move client-facing endpoints to `onCall`.** If the REST surface must stay (third-party consumers, existing integrations), run it as a *second* function alongside the callables and treat it as a webhook/partner API, not as the app's transport. Do not try to reproduce the error contract over REST by hand — see B3. |
| B3 | **Error envelope: `HttpsError` only; `{ success, data }` explicitly banned** (`envelope-and-naming.md`) | Express REST almost certainly returns HTTP status codes plus a JSON body, often with a `success` flag | If REST is kept, the reconciliation is to emit the *same vocabulary* over HTTP: the `errors-and-logging.md` table already gives the HTTP status per code (`invalid-argument`→400, `unauthenticated`→401, `permission-denied`→403, `not-found`→404, `already-exists`/`aborted`→409, `failed-precondition`→412, `resource-exhausted`→429, `unimplemented`→501, `internal`/`data-loss`/`unknown`→500, `deadline-exceeded`→504, `unavailable`→503, `cancelled`→499). Body: `{ "error": { "code": "resource-exhausted", "message": "…", "details": { … } } }` and **never** HTTP 200 with a failure flag. Then `ApiFailure.fromHttp(status, body.error.code)` maps to exactly the same sealed type, so the client half of section 4 is preserved. ⚠️ NOT IN SKILLS — the skills never sanction a REST envelope; this is the least-damage adaptation. |
| B4 | **Auth + App Check are free on callables; manual on `onRequest`** | Express | With Express you must, per the skills, do it yourself on every route: `getAuth().verifyIdToken(token, true)` (note `checkRevoked: true`) **and** `getAppCheck().verifyToken(req.header('X-Firebase-AppCheck'))`. Write it once as Express middleware, and make the middleware throw the same code vocabulary as B3. There is no `enforceAppCheck` shortcut and no `consumeAppCheckToken` equivalent — replay protection for money/credit endpoints has to be rebuilt on the client-generated `requestId` ledger from §1.10. |
| B5 | **One exported function per file, deploys/logs/IAM per function** (`project-layout.md`) | One Express app = one deployed function | You lose `--only functions:createNote`, per-function `memory`/`timeoutSeconds`/`maxInstances`/`secrets`, per-function log filtering and per-function alerting — and `maxInstances`, which `firebase-deploy-pro` calls the primary cost cap, becomes global to the whole API. Reconciliation: split at least the expensive/asymmetric endpoints (AI, OCR, task enqueue, anything with a secret) into their own `onCall`s with their own options, and keep the Express app for the cheap uniform CRUD. `secrets: [...]` must be declared on the Express function for every secret any route reads. |
| B6 | **Function naming: camelCase verbs, deployed name == export name == client string** | REST paths `/api/notes`, `POST /notes/:id` | Incompatible naming models. If you move to callables, rename: `POST /notes` → `createNote`, `GET /notes` → `listNotes`. If you keep REST, the `Fn` constants table in Dart becomes a table of paths+methods instead, and the `envelope-and-naming.md` rules about dots and versioning become "no path-based versioning; add `/v2/createNote` as a new route and keep the old one" — same additive/breaking discipline, different surface. |
| B7 | **Streaming callables (`sendChunk` / `acceptsStreaming`)** | Express would use SSE or chunked responses | If AI streaming is needed, this is the strongest single argument for `onCall`: the Dart `stream<T,R>` API exists and is documented; over `dio` you would hand-roll SSE parsing and lose the `Chunk`/`Result` sealed guarantee. Recommendation: make the AI endpoints callables even if the rest stays REST. |
| B8 | **Idempotency via server-side `ref.create` on a client `requestId`** | REST typically relies on HTTP semantics | Portable as-is — it is a data-layer pattern, not a transport one. **Do it regardless**, because `dio` retries are easier to configure than callable retries and non-idempotent double-creates get worse, not better, with REST. |
| B9 | **Firestore `Timestamp` never crosses the boundary; ISO-8601 only** | Express + `res.json()` will serialise a `Timestamp` as `{_seconds, _nanoseconds}` silently | Same rule, higher risk: with `res.json(snap.data())` there is no error, just a wrong shape. Enforce explicit output mappers per endpoint — the skills' *"Never return `snapshot.data()` directly"* is even more important here. |
| B10 | **vitest + `firebase-functions-test` 3.x + `fn.run()` + `emulators:exec`** | Likely jest, and Express routes tested with supertest | Keep the pyramid and the `demo-` project rule regardless. The handler/wrapper split (`createNoteHandler(ctx, input, deps)`) is transport-agnostic and is exactly what makes an Express→callable migration cheap later — adopt it first, whatever the test runner. If jest stays, the only losses are vitest-specific config (`fileParallelism: false` → jest's `--runInBand`). |
| B11 | **`defineSecret`/`defineString` params, `functions.config()` removed** | A JS Express app may still use `functions.config()` or raw `process.env` | Non-negotiable: `functions.config()` is *"removed for new deployments from March 2026."* The `config-and-secrets.md` migration recipe (5 steps) applies verbatim and is independent of TS vs JS. |

### 7.3 Conflicts with the existing client (`flutter_bloc` + `dio` + `go_router`)

| # | Skill position | Existing app | Reconciliation |
|---|---|---|---|
| F1 | **`dio` vs `cloud_functions`** | `dio` HTTP client | If the backend stays REST (B2), `dio` stays and the entire `flutter-firebase-contract/references/callables.md` is inapplicable — but the parts that survive are the important ones: the request/response model discipline (§4.2), ISO-8601 dates, tolerant response enums, nullability copied from the schema, and the sealed `ApiFailure`. Build `ApiFailure.fromDio(DioException)` alongside `ApiFailure.fromFunctions` in the **same file** (sealed classes require it) so both transports converge on one exhaustive switch. If some endpoints become callables (B7), the two coexist behind the same repository interface and the presentation layer cannot tell. ⚠️ NOT IN SKILLS: `dio` is never mentioned in any skill. |
| F2 | **The `call<T>()` unchecked-cast trap and the `as num` / `cast<String>()` traps** | `dio` + `jsonDecode` | The traps are **worse** with `dio`, not better: `jsonDecode` returns `Map<String, dynamic>` with the same `int`-vs-`double` ambiguity and the same `List<dynamic>`. The three-row trap table in §4.3 applies verbatim, and `strict-casts: true` from the prescribed `analysis_options.yaml` is what turns them into compile errors. Keep both. |
| F3 | **App Check and ID tokens are attached automatically** | `dio` sends whatever you put in an interceptor | With `dio` you must add an interceptor that calls `FirebaseAuth.instance.currentUser?.getIdToken()` and `FirebaseAppCheck.instance.getToken()` per request, and a limited-use token (`getLimitedUseToken()`) for the replay-protected endpoints. This reintroduces exactly the bug class the skills warn about (*"Sending `uid` in a callable request"*, *"you never build an `Authorization` header"*). Write the interceptor once, in the data layer, and never let a repository set headers. ⚠️ NOT IN SKILLS. |
| F4 | **`flutter_bloc` vs Riverpod** | `flutter_bloc` | Not a conflict to resolve — `riverpod-pro` is explicitly out of scope. Carry across the framework-agnostic items listed in §5.8: feature-first layering with one-way arrows, repository interfaces, DI at the composition root with loud failure, no `BuildContext` in the state layer, navigation as a widget concern (`BlocListener` → `context.go(...)`), side effects in listeners not in `build`, **state replaced never mutated** (matters for `Equatable` bloc states with list fields), liveness check after every async gap (`if (isClosed) return;` before `emit` — the Bloc analogue of `if (!ref.mounted) return;`), and sealed state hierarchies switched exhaustively with no `default`. |
| F5 | **go_router 18.0.x requires `material_ui ^1.0.0` + `cupertino_ui ^1.0.0`** | Existing `go_router` on `package:flutter/material.dart` | This is the highest-friction client conflict: *"its classes are distinct types from the package's, so mixing the two produces 'argument type X is not the type X' errors."* Either (a) stay on the current go_router major and defer the Flutter 3.47 package migration — in which case `flutter-widgets-pro`'s import rule, `material_ui`-based examples and several deprecations (`scrollCacheExtent`, `findItemIndexCallback`, `onReorderItem`, `headingLevel`) do not apply yet — or (b) run `dart fix --apply --code=migrate_design_widgets` across `lib/` and `test/` in one commit and go to go_router 18. **It must be all-or-nothing**; a partial migration is the failure mode the skills describe. Decide this before writing any widget code, because four skills' examples assume the new imports. |
| F6 | **`extra` carrying a model is a finding; ids in the path** | Common go_router practice | Framework-compatible, just a discipline change. Audit every `push`/`go` with `extra:` and replace with a path parameter + a load on the destination. Required anyway for deep links and notification taps. |
| F7 | **Typed routes via `go_router_builder`** | Likely string paths | Optional in the skills (they present both), but if adopted note it needs `build_runner`, the `_$RouteName` mixin, and `dart run build_runner build --delete-conflicting-outputs` — and the generated files go in `analyzer.exclude`, not `.gitignore`. |
| F8 | **Riverpod 3 auto-retry (10 attempts)** | N/A with Bloc | Not applicable, but the *underlying* requirement is: a form submission must fail fast and non-idempotent calls must not silently retry. With `dio` the equivalent hazard is a retry interceptor — configure it to honour the `isRetryable` predicate from §4.4 (only `TransientFailure`, `ServerFailure`, `ConflictFailure`) and **never** to retry a non-idempotent call that lacks a client-generated `requestId`. |
| F9 | **`flutter_lints` vs `very_good_analysis`** | Whatever the app has | `dart-pro` accepts either, but the `analyzer.language` block (`strict-casts`, `strict-inference`, `strict-raw-types`) and the `errors:` promotions are what actually matter and are independent of the base set. Adopt the file in §5.4 and expect a large first-run diff — `strict-casts` alone will flag every `jsonDecode` site, which is the point. |
| F10 | **`firebase_remote_config` absent from the mandated version matrix** | Needed by the AdMob port (§6.5) | ⚠️ NOT IN SKILLS: the matrix in `flutter-firebase-contract/references/setup.md` lists six FlutterFire packages and does not include `firebase_remote_config`. The matrix's own rule — *"All of them require `firebase_core ^4.14.0` or newer — bump the whole set together, never one plugin alone"* — means you must add it at a version compatible with `firebase_core ^4.15.0` and bump it with the rest of the block. |
| F11 | **AdMob skill assumes iOS-only privacy configuration** | Flutter ships Android too | ⚠️ NOT IN SKILLS: the entire `consent-privacy.md` (Info.plist, App Store Connect labels, GMA privacy manifest) and `AdUnitIDs`' Info.plist tier have no Android half. The port needs an Android app-ID meta-data entry, Android test unit IDs, a Play Data safety declaration, and a second platform tier in the unit-ID resolver. The *policy* rules (timing, placement, no PII, native rendering, SSV) are platform-neutral and port unchanged. |

### 7.4 The three decisions that unblock everything else

1. **Transport**: `onCall` or Express REST. Everything in §1.5, §1.6 and §4 either applies directly or needs the B3/B4 hand-built substitute. The skills' position is unambiguous (`onCall`), and the AI streaming path (B7) and App Check story (B4) are the concrete costs of the alternative.
2. **Language on the backend**: TS or JS. Without TS the zod-as-source-of-truth contract, `z.infer` types and the contract snapshot tests are not reconstructible.
3. **Flutter 3.47 package migration**: `material_ui`/`cupertino_ui` + go_router 18, or neither. Four skills' widget, test and contract examples assume the migrated imports, and a half-migration produces type errors that read like nonsense.

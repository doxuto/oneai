# Errors and logging

`HttpsError` is the only error type a callable should let escape. Its `code` maps 1:1 to `FunctionsErrorCode` on the iOS side, its `message` is shown to developers (not users), and its `details` is an optional JSON object the client can decode. Anything else that escapes the handler becomes `internal` with message `"INTERNAL"` — the real error stays in Cloud Logging, the client learns nothing, and you cannot distinguish "bug" from "Firestore down" from "quota hit".

## `HttpsError`

```ts
import { HttpsError, type FunctionsErrorCode } from "firebase-functions/v2/https";

throw new HttpsError(code, message, details?);
//                   ^ FunctionsErrorCode  ^ string  ^ unknown (JSON-serialisable)
```

The `details` argument must be plain JSON: no `Error` instances, no `Timestamp`, no class instances. Keep it small — it travels in the response body and appears in client logs.

## Code table

| Code | HTTP | Use when | iOS UX | Retry |
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

The iOS retry policy per code lives in `firebase-ios-contract` → `references/error-mapping.md`; keep the two tables in agreement.

## Mapping internal errors

Wrap every external call and translate. A small helper keeps handlers readable:

```ts
// src/lib/errors.ts
import { HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/logger";

interface GrpcLike { code?: number; message?: string }

/** Firestore/gRPC status codes → HttpsError. */
export function mapFirestoreError(err: unknown, context: Record<string, unknown>): HttpsError {
  const code = (err as GrpcLike).code;
  switch (code) {
    case 5:  return new HttpsError("not-found", "Not found");
    case 6:  return new HttpsError("already-exists", "Already exists");
    case 7:  return new HttpsError("permission-denied", "Permission denied");
    case 8:  return new HttpsError("resource-exhausted", "Quota exceeded");
    case 9:  return new HttpsError("failed-precondition", "Precondition failed");
    case 10: return new HttpsError("aborted", "Conflict, retry");
    case 4:  return new HttpsError("deadline-exceeded", "Timed out");
    case 14: return new HttpsError("unavailable", "Service unavailable");
    default:
      logger.error("firestore.unmapped", { ...context, grpcCode: code, error: String(err) });
      return new HttpsError("internal", "Internal error");
  }
}

/** Rethrow HttpsError untouched; map anything else. */
export function rethrow(err: unknown, context: Record<string, unknown>): never {
  if (err instanceof HttpsError) throw err;
  throw mapFirestoreError(err, context);
}
```

Usage:

```ts
try {
  await db.runTransaction(async (tx) => { ... });
} catch (err) {
  rethrow(err, { fn: "createNote", uid });
}
```

Provider SDKs (Gemini, Vision, RevenueCat) have their own shapes. Map HTTP 429 → `resource-exhausted`, 5xx / network → `unavailable`, 4xx you caused → `internal` (it is your bug, not the user's), and safety-blocked generations → `failed-precondition` with `details.reason: "safety"`.

Zod errors are already handled by `parse()` in `callable.md`. Do not let a `ZodError` escape — it becomes `internal`.

## Never leak

- Stack traces, file paths, provider error messages, SQL, Firestore paths of other users, secret names, internal hostnames — none of these go in `message` or `details`.
- `message` is for the developer reading Xcode logs: short, English, no user data. The app shows its own localised copy keyed on `code` (+ `details.reason`).
- `details` is a contract, not a dump. Document each key per function. Common keys: `field`, `issues`, `reason`, `limit`, `resetAt`, `minVersion`, `retryAfterSeconds`.
- Never put the caught error object into `details` (`details: err`) — it serialises the message and sometimes the config that produced it.

## Structured logging

```ts
import { logger } from "firebase-functions/logger";

logger.debug("note.create.start", { uid });                       // hidden unless log level lowered
logger.info("note.created", { uid, noteId, tagCount });           // normal events
logger.warn("quota.near", { uid, used: 48, limit: 50 });          // something to look at
logger.error("gemini.failed", { uid, model, status, error: String(err) });   // Error Reporting picks this up
```

Rules:

- First argument is a stable event name: `domain.thing.event`, lower-case, dot-separated. Grep-able and filterable in Logs Explorer with `jsonPayload.message="note.created"`.
- Second argument is a flat object of fields. Nested objects are fine but keep depth ≤ 2. Fields land under `jsonPayload` and are queryable.
- Include `uid` on every user-scoped log. Do not include email, display name, prompt text, note contents, tokens, or any secret.
- `String(err)` or `err instanceof Error ? err.message : String(err)` for the error field. Passing the raw `Error` object also works and includes the stack, which is fine for `logger.error` in production logs (they are not client-visible), but strip it for anything that might be forwarded.
- `console.log(obj)` prints `[object Object]` or a multi-line string that Cloud Logging cannot index. `console.log("string")` is acceptable for one-off debugging; remove before merge.
- Severity: `debug` for tracing, `info` for business events, `warn` for handled anomalies, `error` for failures that need a human. Do not `error` on expected client mistakes (`invalid-argument`, `unauthenticated`) — that floods Error Reporting.

### Log the request once, at the end

```ts
const started = Date.now();
try {
  const result = await work();
  logger.info("chat.completed", { uid, ms: Date.now() - started, chars: result.text.length });
  return result;
} catch (err) {
  logger.error("chat.failed", { uid, ms: Date.now() - started, error: String(err) });
  rethrow(err, { fn: "chat", uid });
}
```

The platform already logs one line per invocation with status and latency; your `info` line adds the domain fields.

## Error Reporting

- Any uncaught exception, and any `logger.error` with an `Error` object, creates an Error Reporting entry grouped by stack. `HttpsError` thrown deliberately is logged at `warning` by the SDK and not reported — correct, those are client errors.
- To make an expected server-side failure appear in Error Reporting without crashing the request, `logger.error("event", { error: err })` with the real `Error` instance.
- Set up an alert on error-rate per function in Cloud Monitoring rather than reading logs by hand.
- `firebase functions:log --only chat` tails a single function; add `-n 200` for history.

## `onRequest` error handling

The SDK does not convert `HttpsError` to an HTTP status inside `onRequest`. Catch and translate with the `sendError` helper in `http.md`. Unhandled rejections in `onRequest` become a 500 with a generic body.

## Triggers and retries

Event functions (`onDocumentWritten`, `onObjectFinalized`, `onSchedule`, `onTaskDispatched`) have no client to receive an `HttpsError`. Throwing there means: with `retry: true` (event triggers) or `retryConfig` (tasks), the event is redelivered; otherwise it is dropped. So:

- Throw only for transient failures you want retried (upstream 5xx, `unavailable`).
- Catch, log with `logger.error`, and return normally for permanent failures (bad data, invalid image) — retrying a permanent failure burns money until the retry window closes.
- Write the failure into the status document the client is watching (`status: "failed", error: { code, message }`) so the iOS side can react.

## Does not exist / common mistakes

- `throw new functions.https.HttpsError(...)` — v1 namespace. Import `HttpsError` from `firebase-functions/v2/https`.
- `new HttpsError("INVALID_ARGUMENT", ...)` — codes are lowercase kebab-case strings. TypeScript rejects the uppercase form.
- `new HttpsError(400, ...)` — not a number.
- `throw new Error("Not found")` in a callable — arrives as `internal` / `"INTERNAL"`.
- `details: err` or `details: { stack: err.stack }` — leaks internals.
- `logger.log(...)` — the method is `logger.info`. (`logger.write({ severity, message })` exists for custom severities; rarely needed.)
- `functions.logger` from the v1 default import — works, but the bundle standard is `firebase-functions/logger`.
- Re-throwing an `HttpsError` with a new code "to be safe" — you lose the original, deliberate classification. `if (err instanceof HttpsError) throw err;` first.

# Threat checklist

Walk this top to bottom for a full review. Each item is a yes/no; a "no" is a finding at the stated severity. Items are ordered by blast radius: unauthenticated data access first, cost and hygiene last. Cite the reference file when reporting.

## A. Unauthenticated and cross-user access (critical)

- [ ] `firestore.rules` ends with `match /{document=**} { allow read, write: if false; }` and `storage.rules` ends with `match /{allPaths=**} { allow read, write: if false; }`. — `firestore-rules.md`, `storage-rules.md`
- [ ] No rule contains `allow read` / `allow write` / `allow list` with `if true` or `if request.auth != null` alone on a path holding user data. — `firestore-rules.md`
- [ ] Every user-data path is owner-scoped by **path segment** (`users/{uid}`) or by `resource.data.ownerId == request.auth.uid`, and every `list` on the latter has a matching `where` in the iOS query. — `firestore-rules.md`
- [ ] Every `onCall` handler throws `unauthenticated` before reading `request.data`; no `request.auth.uid` without the guard; no `(data, context)` v1 signature. — `auth-in-functions.md`
- [ ] Every `onRequest` handler that acts on behalf of a user calls `verifyIdToken`; no uid, email, or role is accepted from body/query/headers other than the bearer token. — `auth-in-functions.md`
- [ ] No callable accepts a `uid` in `request.data` to act on another user unless the caller's claim authorises it, and that claim is checked. — `auth-in-functions.md`
- [ ] Collection-group rules exist for every `collectionGroup` query the app runs, and docs carry the `ownerId` field the rule needs. — `firestore-rules.md`
- [ ] No download URLs (with `token=`) or long-lived signed URLs stored in documents readable by other users. — `storage-rules.md`

## B. Privilege escalation (critical)

- [ ] `role`, `plan`, `credits`, `isVerified`, `flags`, `status`, `schemaVersion`, `createdAt`, `ownerId` are in the `update` deny-list (`diff().affectedKeys().hasAny([...])`) and absent from the `create` allow-list (`keys().hasOnly([...])`). — `firestore-rules.md`
- [ ] Roles are read from `request.auth.token.<claim>` in rules and callables, never from a document field the client can write. — `auth-in-functions.md`
- [ ] `setCustomUserClaims` is called only from admin-gated callables, blocking triggers, or scripts — never with values derived from `request.data` without an admin check. — `auth-in-functions.md`
- [ ] Claims object stays under 1000 bytes and contains only authorization data. — `auth-in-functions.md`
- [ ] After a claim change the server signals the client (`claimsUpdatedAt`) and the iOS app force-refreshes; for downgrades `revokeRefreshTokens` is called. — `auth-in-functions.md`
- [ ] Anonymous users (`sign_in_provider == 'anonymous'`) are restricted in rules and callables: no purchases, no sharing, small quotas. — `auth-in-functions.md`, `firestore-rules.md`
- [ ] Account merge / link flows never trust two uids from the client. — `auth-in-functions.md`

## C. Input validation (high)

- [ ] Every callable validates `request.data` with zod (`safeParse`) and throws `invalid-argument` with `flatten()` details; sizes and array lengths are bounded. — SKILL.md core instructions
- [ ] Rules validate client-created docs: `keys().hasOnly`, `hasAll`, `is string/int/timestamp/list/map`, `.size()` bounds, controlled vocabularies with `in`. — `firestore-rules.md`
- [ ] Server timestamps enforced with `== request.time`; client-supplied `createdAt` rejected. — `firestore-rules.md`
- [ ] Storage rules cap `request.resource.size` and `contentType`; the processing trigger sniffs bytes rather than trusting `contentType`. — `storage-rules.md`
- [ ] Custom Storage metadata keys are allow-listed and treated as untrusted in triggers. — `storage-rules.md`
- [ ] Path parameters from triggers (`event.params.uid`) are used for authorization, not values inside the document body. — `firestore-data-pro` → `triggers.md`

## D. App Check (high)

- [ ] Provider factory set **before** `FirebaseApp.configure()`; `AppCheckDebugProvider` only under `#if DEBUG`; App Attest entitlement present with the right environment. — `app-check.md`
- [ ] Every client-facing callable has `enforceAppCheck: true` (or a documented soft-rollout with logging). — `app-check.md`
- [ ] Money/credit/one-shot callables use `consumeAppCheckToken: true` **and** the iOS `HTTPSCallableOptions(requireLimitedUseAppCheckTokens: true)`. — `app-check.md`
- [ ] `onRequest` endpoints for the app verify `X-Firebase-AppCheck` with `getAppCheck().verifyToken`. — `app-check.md`
- [ ] Console enforcement is on for Firestore, Storage, and Authentication (or a dated plan exists after checking unverified-request metrics). — `app-check.md`
- [ ] Debug tokens are registered only on the dev project, not committed, and pruned. — `app-check.md`
- [ ] No `enforceAppCheck` on triggers/scheduled/task functions; no `request.appCheck` in rules; no assumption that App Check replaces auth or rules. — `app-check.md`

## E. Account lifecycle (high — App Store rejection risk)

- [ ] In-app account deletion exists and completes without contacting support (guideline 5.1.1(v)). — `sign-in-with-apple-and-deletion.md`
- [ ] For Apple-linked users the app calls `revokeToken(withAuthorizationCode:)` with a **fresh** authorization code **before** deletion. — `sign-in-with-apple-and-deletion.md`
- [ ] `deleteAccount` callable: recent-sign-in check via `auth_time`, freezes the account, deletes Storage prefixes, `recursiveDelete` on `users/{uid}`, deletes field-keyed docs, notifies external processors, then `deleteUser`. — `sign-in-with-apple-and-deletion.md`
- [ ] A safety net exists for out-of-band auth deletions (Delete User Data extension or v1 `auth.user().onDelete`), configured with the same paths. — `sign-in-with-apple-and-deletion.md`
- [ ] Apple `fullName`/`email` are captured on first sign-in only and relay emails are treated as verified. — `sign-in-with-apple-and-deletion.md`
- [ ] Data export is available on request (callable + short-lived signed URL). — `secrets-and-pii.md`

## F. Rate limiting and cost (medium–high)

- [ ] Every callable that calls a model, sends push fan-out, generates signed URLs, or writes many docs consumes a per-user quota **in a transaction, before the work**, with limits derived from the `plan` claim and reduced for anonymous users. — `rate-limiting-and-abuse.md`
- [ ] `resource-exhausted` responses carry `resetsAt` (ISO) so iOS can render the state. — `rate-limiting-and-abuse.md`
- [ ] `maxInstances` is set globally and per expensive function; `concurrency` is low for model-calling handlers; `timeoutSeconds` is bounded. — `rate-limiting-and-abuse.md`
- [ ] Task queue workers have `rateLimits` and `retryConfig`; the enqueuing callable is quota'd too. — `firestore-data-pro` → `task-queues.md`
- [ ] Triggers that write to their own path compare before/after (no infinite loop) and have `maxInstances`. — `firestore-data-pro` → `triggers.md`
- [ ] No single global counter document; quota docs are per user. — `rate-limiting-and-abuse.md`
- [ ] Storage upload volume per user is capped (rules size + count in trigger). — `rate-limiting-and-abuse.md`
- [ ] Listeners on the client are bounded (`request.query.limit` in rules, pagination). — `firestore-rules.md`
- [ ] A Cloud Billing budget alert exists; Cloud Monitoring alerts on invocation count and error rate. — `rate-limiting-and-abuse.md`

## G. Secrets, logging, PII (medium)

- [ ] All API keys / webhook secrets are `defineSecret` in Secret Manager, declared per function via `secrets: [...]`, read with `.value()` inside handlers; no `functions.config()`, no secrets in `.env*`, no keys in source or in the iOS bundle. — `secrets-and-pii.md`
- [ ] Webhook auth uses a constant-time compare and supports rotation. — `secrets-and-pii.md`
- [ ] Logs never contain tokens, headers, secrets, emails, phones, or user content; a redacting wrapper is used; `console.log` of objects is absent. — `secrets-and-pii.md`
- [ ] Client-facing errors are `HttpsError` with fixed messages; provider errors are logged, not returned. — `secrets-and-pii.md`
- [ ] Timestamps returned from callables are ISO strings; no `Timestamp` objects leak (they do not serialise). — `secrets-and-pii.md`
- [ ] Retention: TTL policies on transient collections, Cloud Logging retention set, lifecycle rules on export/backup buckets. — `secrets-and-pii.md`
- [ ] Third-party processors list matches the App Store privacy label and `PrivacyInfo.xcprivacy`. — `secrets-and-pii.md`

## H. Environment hygiene (medium)

- [ ] Separate Firebase projects for dev / staging / prod (`.firebaserc`), separate secrets per project, no shared debug tokens across projects.
- [ ] Rules and indexes are deployed from the repo (`firebase deploy --only firestore:rules,firestore:indexes,storage`), not edited in the console.
- [ ] Rules have unit tests per principal (signed-out, anonymous, owner, other user, admin) with `@firebase/rules-unit-testing` under a `demo-` project id, run in CI via `firebase emulators:exec`. — `firebase-testing-pro`
- [ ] Emulator is never treated as an App Check test bed; enforcement is verified against the dev project.
- [ ] Functions are v2 with explicit `region`; no v1 `runWith`, no `firebase-functions/v2/auth`, no mixed v1/v2 options on one function.

## Severity guide

| Severity | Meaning | Examples |
|---|---|---|
| critical | Any principal can read or write data they do not own, or escalate privilege, without a bug elsewhere | A/B items; `allow read: if true` on user data; `role` writable by client |
| high | Requires a valid app user, but lets them cause loss, unbounded cost, or App Store rejection | C, D, E items; missing quota on a Gemini callable; no account deletion |
| medium | Weakens defence in depth or hygiene; exploitable only in combination | F, G, H items; secret in `.env`; token in a log line; no TTL on a ledger |
| low | Style or clarity; no security effect | Naming, duplicated helper functions, comments |

Never inflate: a missing `maxInstances` on a cheap trigger is medium, not high. Never deflate: an `update` rule without the privileged-key deny-list is critical even if the app never sends those keys today.

## Ten-minute triage

When there is no time for the full walk, do these in order and stop at the first failure:

1. Open `firestore.rules`; search for `if true` and `request.auth != null;` — every hit on a user-data path is critical.
2. Check the trailing catch-all deny exists in both rules files.
3. Grep functions for `request.auth.uid` and `request.auth!` — every occurrence without a preceding `if (!request.auth)` is a bug.
4. Grep for `setCustomUserClaims` — every call must sit behind an admin claim check or a blocking trigger.
5. Grep for `enforceAppCheck` — count callables without it.
6. Grep for `functions.config()`, `process.env.` next to key-like names, and `console.log` — secrets and PII hygiene.
7. Confirm a `deleteAccount` (or equivalent) callable exists and calls `deleteUser` last.
8. Grep for `runTransaction` in quota code — quota without a transaction is a race.
9. Grep for `maxInstances` — zero hits means no cost cap anywhere.
10. Open the iOS app entry point: `setAppCheckProviderFactory` before `FirebaseApp.configure()`, debug provider under `#if DEBUG` only.

## What a passing review looks like

- Rules: every path enumerated, helpers at the top, catch-all deny at the bottom, `create` allow-lists and `update` deny-lists on every client-writable document, rules tests per principal in CI.
- Functions: `requireAuth` / `requireRole` helpers used uniformly; zod on every input; `HttpsError` with fixed messages; `log.*` wrapper; `secrets: [...]` declared per function; `maxInstances` everywhere; quota before expensive work.
- App Check: enforced on callables, console enforcement on Firestore/Storage/Auth, limited-use tokens on money paths, debug tokens only on the dev project.
- Lifecycle: Sign in with Apple with nonce, first-sign-in name capture, in-app deletion with Apple revocation and a server-side cascade, safety-net trigger or extension.
- Cost: per-user quota docs, anonymous restrictions, task queues with rate limits, budget alert.

## Reporting

Report each unchecked item as: file → line or `match` path → checklist id (e.g. **B.1**) → before/after. Order the summary A → H, critical first. A review with no A/B findings but several F/G findings should still say clearly that no cross-user access path was found — absence of critical findings is itself useful information.

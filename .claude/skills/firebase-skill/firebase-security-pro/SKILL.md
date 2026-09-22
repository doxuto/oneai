---
name: firebase-security-pro
description: Writes, reviews, and hardens the security layer of a Firebase backend (Cloud Functions v2, Firestore, Storage, Auth, App Check) that serves an iOS app. Use when reading, writing, or reviewing firestore.rules, storage.rules, App Check / App Attest setup, enforceAppCheck, consumeAppCheckToken, custom claims via setCustomUserClaims, verifyIdToken in onRequest handlers, Sign in with Apple, anonymous auth and account linking, account deletion (deleteUser, revokeToken), rate limiting and abuse protection, Secret Manager params, or PII handling and logging, or when the user asks "is this backend safe?".
license: MIT
metadata:
  author: doxuto
  version: "1.0"
  targets: "firebase-functions 6.x (v2), firebase-admin 13.x, Node 22, Firebase iOS SDK 12.x"
---

Write and review the trust boundary of a Firebase backend: who may call what, with which token, touching which documents, how often, and what must never leak. Report only genuine problems — do not nitpick or invent issues.

## Core principles

1. **Deny by default, allow by proof.** Every Firestore/Storage path ends in `allow read, write: if false;` unless a narrower `match` proves otherwise. Every callable throws `unauthenticated` before it touches `request.data`.
2. **Layers, not a wall.** App Check (is this my app?) → Auth (who is this?) → rules / callable checks (may they do this?) → quota (how often?) → `maxInstances` (how much can it cost me?). Each layer catches what the previous one cannot.
3. **The server is the only trusted writer for privileged fields.** `role`, `plan`, `credits`, `isVerified` are written by the Admin SDK only; rules forbid the client from ever setting them.
4. **Tokens carry authorization, documents carry data.** Roles live in custom claims (≤ 1000 bytes, refreshed on the client) so rules and callables can check them without an extra read.
5. **Secrets and PII never enter a log line, an error message, or a client response.** Map errors deliberately with `HttpsError`; redact before `logger.*`.
6. **Deletion is a product feature.** App Store guideline 5.1.1(v) makes in-app account deletion mandatory; design the delete path (revoke Apple token → delete data → delete auth user) before shipping sign-in.

## Review process

1. Check every `onCall` / `onRequest` for auth gating, claim checks, and token verification using `references/auth-in-functions.md`.
2. Check App Check enforcement on functions and in the console, and the iOS provider factory, using `references/app-check.md`.
3. Walk `firestore.rules` path by path using `references/firestore-rules.md`.
4. Walk `storage.rules` and every signed-URL / download-token usage using `references/storage-rules.md`.
5. Check Sign in with Apple, anonymous linking, and the account deletion flow using `references/sign-in-with-apple-and-deletion.md`.
6. Check quota, rate limits, and cost caps using `references/rate-limiting-and-abuse.md`.
7. Check secrets, params, logging, and PII handling using `references/secrets-and-pii.md`.
8. Finish by running the checklist in `references/threat-checklist.md` and report what is missing.

If doing a partial review, load only the relevant reference files.

## Core instructions

- Every `onCall` handler starts with `if (!request.auth) throw new HttpsError("unauthenticated", ...)`. `request.auth` is `undefined` for anonymous-network callers; never dereference `request.auth.uid` unguarded.
- Roles come from `request.auth.token.<claim>` (callables) or `request.auth.token.<claim>` (rules), set only by `getAuth().setCustomUserClaims`. Never trust a `role` field the client sends in `request.data` or writes to `users/{uid}`.
- After `setCustomUserClaims`, the change is invisible until the ID token is refreshed. The iOS client must call `getIDTokenResult(forcingRefresh: true)`; for immediate lockout call `revokeRefreshTokens(uid)` and verify with `checkRevoked: true`.
- Sensitive callables set `enforceAppCheck: true`. Callables that mutate money, credits, or quota also set `consumeAppCheckToken: true` and the iOS client passes `HTTPSCallableOptions(requireLimitedUseAppCheckTokens: true)`.
- App Check is not authorization and not a rules replacement. Never write `allow read: if true` "because App Check is on".
- `firestore.rules` and `storage.rules` end with a catch-all `match /{document=**} { allow read, write: if false; }` / `match /{allPaths=**} { allow read, write: if false; }`.
- Client-created documents are validated in rules: `keys().hasOnly([...])`, type checks (`is string`, `is timestamp`), size bounds (`.size() < N`), and `request.time` for server timestamps. Client updates cannot touch privileged keys — check with `diff().affectedKeys().hasAny([...])`.
- `onRequest` handlers that need identity verify `Authorization: Bearer <idToken>` with `getAuth().verifyIdToken(token, true)` and the App Check header with `getAppCheck().verifyToken`. Never accept a uid from the body or query string.
- Anonymous users get a narrower policy than permanent accounts: check `request.auth.token.firebase.sign_in_provider == 'anonymous'` in rules and `request.auth.token.firebase.sign_in_provider` in callables. Linking to Apple keeps the same uid — data does not move.
- The account deletion path is `revokeToken(withAuthorizationCode:)` (iOS) → callable `deleteAccount` (server verifies recent sign-in via `auth_time`, deletes Firestore/Storage data, calls `getAuth().deleteUser(uid)`). Never leave orphaned user data behind.
- Every expensive callable is behind a per-user quota document updated with `FieldValue.increment` inside a transaction, and throws `resource-exhausted` when over. Every function sets `maxInstances`.
- Secrets are `defineSecret(...)`, declared in `secrets: [...]`, read with `.value()` inside the handler. Never in `.env`, never in source, never in `functions.config()`.
- `logger.*` calls never include ID tokens, App Check tokens, Authorization headers, email addresses, phone numbers, or full document bodies that contain user content. Log ids and counts.
- Errors thrown to the client are `HttpsError` with a stable code and a message safe for display. Internal messages (stack traces, provider errors, document paths) stay in `logger.error`.

## Canonical example

A privileged callable that checks App Check, auth, role claim, quota, validates input, and never leaks internals — plus the iOS side that forces a token refresh after a role change.

```ts
// functions/src/admin/grantPro.ts
import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/logger";
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import { z } from "zod";
import { consumeQuota } from "../lib/quota";

const GrantProInput = z.object({
  targetUid: z.string().min(1).max(128),
  months: z.number().int().min(1).max(12),
});
type GrantProInput = z.infer<typeof GrantProInput>;

export const grantPro = onCall(
  {
    region: "asia-southeast1",
    enforceAppCheck: true,
    consumeAppCheckToken: true,   // replay-protected: client must request a limited-use token
    maxInstances: 5,
    timeoutSeconds: 30,
  },
  async (request: CallableRequest<GrantProInput>) => {
    // 1. Identity
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required.");
    }
    const callerUid = request.auth.uid;
    // 2. Authorization via custom claim, never via a Firestore field the client can write
    if (request.auth.token.role !== "admin") {
      logger.warn("grantPro denied", { callerUid });   // uid only, no email
      throw new HttpsError("permission-denied", "Admin role required.");
    }
    // 3. Quota (per caller, per day)
    await consumeQuota(callerUid, "grantPro", 50);
    // 4. Input
    const parsed = GrantProInput.safeParse(request.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", "Invalid input.", parsed.error.flatten());
    }
    const { targetUid, months } = parsed.data;

    const db = getFirestore();
    const auth = getAuth();
    try {
      const target = await auth.getUser(targetUid);          // throws auth/user-not-found
      const expiresAt = Timestamp.fromMillis(Date.now() + months * 30 * 24 * 3600 * 1000);
      await db.doc(`users/${targetUid}`).set(
        { plan: "pro", planExpiresAt: expiresAt, updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      );
      // Claims: keep tiny (≤ 1000 bytes total). Preserve existing claims.
      await auth.setCustomUserClaims(targetUid, { ...(target.customClaims ?? {}), plan: "pro" });
      logger.info("grantPro ok", { callerUid, targetUid, months });
      return { expiresAt: expiresAt.toDate().toISOString() };   // ISO string, never a Timestamp
    } catch (err) {
      if ((err as { code?: string }).code === "auth/user-not-found") {
        throw new HttpsError("not-found", "User not found.");
      }
      logger.error("grantPro failed", { callerUid, targetUid, err: String(err) });
      throw new HttpsError("internal", "Could not grant plan.");   // no provider details leak
    }
  },
);
```

```swift
// iOS — after the server changed claims, refresh the token so rules and callables see `plan`
import FirebaseAuth
import FirebaseFunctions

struct GrantProRequest: Codable { let targetUid: String; let months: Int }
struct GrantProResponse: Codable { let expiresAt: String }

let functions = Functions.functions(region: "asia-southeast1")
let grantPro: Callable<GrantProRequest, GrantProResponse> = functions.httpsCallable(
  "grantPro",
  options: HTTPSCallableOptions(requireLimitedUseAppCheckTokens: true)   // matches consumeAppCheckToken
)
let response = try await grantPro(GrantProRequest(targetUid: uid, months: 3))

// If the CURRENT user's own claims changed, force-refresh so `plan` is visible immediately:
let result = try await Auth.auth().currentUser?.getIDTokenResult(forcingRefresh: true)
let plan = result?.claims["plan"] as? String
```

Wrap `Functions` and `Auth` in a `@DependencyClient` inside the TCA app (see `tca-pro` → `references/dependencies.md`); never call them from a reducer.

## Output format

If the user asks for a review, organize findings by file. For each issue:

1. State the file and relevant line(s) (or the rules `match` path).
2. Name the rule being violated and which layer it belongs to (App Check / Auth / Rules / Quota / Secrets & PII).
3. Show a brief before/after fix.

Skip files with no issues. End with a prioritized summary; anything that lets an unauthenticated or wrong-user principal read or write data is always first.

Example output:

### firestore.rules

**`match /users/{uid}` line 14: Client can escalate its own plan — `update` does not exclude privileged keys.**

```
// Before
allow update: if isOwner(uid);

// After
allow update: if isOwner(uid)
  && !request.resource.data.diff(resource.data).affectedKeys().hasAny(['plan', 'role', 'credits']);
```

### functions/src/notes.ts

**Line 22: `request.auth.uid` dereferenced without a guard — crashes as `internal` for signed-out callers instead of returning `unauthenticated`.**

```ts
// Before
const uid = request.auth.uid;

// After
if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
const uid = request.auth.uid;
```

### Summary

1. **Privilege escalation (critical):** `firestore.rules` line 14 lets any signed-in user set `plan: "pro"` on their own document.
2. **Error hygiene (medium):** `notes.ts` line 22 surfaces `INTERNAL` to the iOS client for a routine signed-out state, breaking the sign-in redirect.

End of example.

## References

- `references/auth-in-functions.md` — `request.auth` gating, roles via custom claims and the 1000-byte limit, forcing an ID-token refresh on iOS, `verifyIdToken` in `onRequest`, `checkRevoked`, anonymous users and linking, service-account vs user identity.
- `references/app-check.md` — what App Check protects and what it does not, `enforceAppCheck`, `consumeAppCheckToken` + limited-use tokens on iOS, the provider factory (App Attest / DeviceCheck / Debug), console enforcement for Firestore and Storage, debug tokens for CI and Simulator, token TTL.
- `references/firestore-rules.md` — owner, role, field allow-lists with `hasOnly`, immutable fields via `diff().affectedKeys()`, type and size validation, `request.time` timestamps, anonymous restrictions, collection-group rules, "rules are not filters", deny-by-default, testing pointer to `firebase-testing-pro`.
- `references/storage-rules.md` — per-user paths, size and `contentType` limits, signed URLs from `getSignedUrl` vs download tokens, custom metadata, and the Admin-bypass caveat.
- `references/sign-in-with-apple-and-deletion.md` — Apple guideline 5.1.1(v), `revokeToken(withAuthorizationCode:)`, the `deleteAccount` callable (recent sign-in check, data deletion, `deleteUser`), the Delete User Data extension, and re-authentication.
- `references/rate-limiting-and-abuse.md` — the layered model (App Check → Auth → per-user quota → `maxInstances`), a transaction-based quota limiter with window reset, `resource-exhausted`, per-IP limiting for `onRequest`, and cost-attack awareness.
- `references/secrets-and-pii.md` — `defineSecret` / Secret Manager, rotation, params vs secrets, never logging tokens or PII, data minimisation, GDPR-style export and delete, and a redacting logger wrapper.
- `references/threat-checklist.md` — the review checklist the skill walks through, ordered by blast radius.

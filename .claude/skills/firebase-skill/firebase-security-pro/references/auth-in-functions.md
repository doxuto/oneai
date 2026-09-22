# Auth inside Cloud Functions v2

Targets firebase-functions 6.x (`firebase-functions/v2/https`), firebase-admin 13.x (`firebase-admin/auth`), Firebase iOS SDK 12.x.

## `request.auth` in `onCall`

The callable SDK verifies the Firebase ID token for you and populates `request.auth`. It is `undefined` when no valid token was sent. There is no `context` argument in v2.

```ts
import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";

export const listNotes = onCall({ region: "asia-southeast1" }, async (request: CallableRequest<unknown>) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in required.");
  }
  const uid = request.auth.uid;                       // string, safe after the guard
  const token = request.auth.token;                   // DecodedIdToken: iss, aud, auth_time, sub, email?, email_verified?, firebase.sign_in_provider, plus custom claims
  const provider = token.firebase.sign_in_provider;   // "anonymous" | "apple.com" | "password" | "google.com" | "custom" | ...
  return { uid, provider };
});
```

Facts about `request.auth.token`:

- `token.uid` and `token.sub` are the same as `request.auth.uid`.
- `token.email` and `token.email_verified` may be absent (Sign in with Apple with "Hide My Email" still gives a relay email; anonymous gives none). Never require `email` unless the product requires it.
- `token.auth_time` is the Unix time (seconds) of the last **sign-in**, not the last token refresh. Use it for "recent sign-in" checks (see `sign-in-with-apple-and-deletion.md`).
- Custom claims appear at the top level: `token.role`, `token.plan`. They are `unknown` in TypeScript — narrow them.

Helper used everywhere:

```ts
export function requireAuth(request: CallableRequest<unknown>): { uid: string; token: CallableRequest["auth"] extends infer A ? NonNullable<A>["token"] : never } {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
  return { uid: request.auth.uid, token: request.auth.token };
}

export function requireRole(request: CallableRequest<unknown>, role: string): string {
  const { uid, token } = requireAuth(request);
  if (token.role !== role) throw new HttpsError("permission-denied", `${role} role required.`);
  return uid;
}
```

## Roles via custom claims

Set claims with the Admin SDK only. The claims object is serialized into the ID token, so it must stay small.

```ts
import { getAuth } from "firebase-admin/auth";

// Whole object is replaced — merge with the existing claims if you want to keep them.
const user = await getAuth().getUser(uid);
await getAuth().setCustomUserClaims(uid, { ...(user.customClaims ?? {}), role: "admin" });
// Remove a claim: pass the object without it (or `null` to clear everything).
await getAuth().setCustomUserClaims(uid, null);
```

Hard limits and rules:

- The custom claims payload must be **≤ 1000 bytes** when JSON-serialized, and must not use reserved OIDC keys (`sub`, `iss`, `aud`, `exp`, `iat`, `auth_time`, `firebase`, …). `setCustomUserClaims` throws if either is violated.
- Claims are for **authorization**, not for data. Store `role`, `plan`, maybe `orgId`. Do not store display names, feature flags per document, or arrays of ids.
- Claims propagate only through a new ID token. A token already issued stays valid (with old claims) until it expires (1 hour) or the client refreshes it.
- Rules read claims as `request.auth.token.role`; callables read `request.auth.token.role`. Same token, no extra Firestore read.
- Mirror the claim into `users/{uid}` for UI (e.g. `plan: "pro"`) if you need to query by it, but rules must forbid the client from writing that field. The claim is the source of truth.

## Forcing a token refresh on iOS

After the server changes claims for the **currently signed-in user**, the client must refresh or it keeps the stale token for up to an hour.

```swift
import FirebaseAuth

// 1. After the callable that changed the claims returns:
let result = try await Auth.auth().currentUser?.getIDTokenResult(forcingRefresh: true)
let role = result?.claims["role"] as? String

// 2. Or observe token changes app-wide (fires on refresh, sign-in, sign-out):
let handle = Auth.auth().addIDTokenDidChangeListener { auth, user in
  Task { _ = try? await user?.getIDTokenResult() }   // cached unless expired
}
```

Pattern for the server to *signal* a refresh: write `users/{uid}.claimsUpdatedAt = serverTimestamp()` in the same call that sets claims; the iOS app listens to its own user doc and calls `getIDTokenResult(forcingRefresh: true)` when that field changes. Inside TCA this belongs in an `AuthClient` dependency (`tca-pro` → `references/dependencies.md`).

## `verifyIdToken` in `onRequest`

`onRequest` does no token handling. Verify manually and never accept a uid from the body or query string.

```ts
import { onRequest, HttpsError } from "firebase-functions/v2/https";
import { getAuth, type DecodedIdToken } from "firebase-admin/auth";
import { logger } from "firebase-functions/logger";

async function authenticate(req: { headers: Record<string, string | string[] | undefined> }): Promise<DecodedIdToken> {
  const header = req.headers.authorization;
  const value = Array.isArray(header) ? header[0] : header;
  if (!value?.startsWith("Bearer ")) throw new HttpsError("unauthenticated", "Missing bearer token.");
  const idToken = value.slice("Bearer ".length);
  try {
    // checkRevoked = true costs one Auth backend call per request; use it on sensitive endpoints only.
    return await getAuth().verifyIdToken(idToken, true);
  } catch (err) {
    logger.warn("verifyIdToken failed", { code: (err as { code?: string }).code });   // never log the token
    throw new HttpsError("unauthenticated", "Invalid or expired token.");
  }
}

export const exportData = onRequest(
  { region: "asia-southeast1", cors: false, invoker: "public", maxInstances: 5 },
  async (req, res) => {
    try {
      const decoded = await authenticate(req);
      res.status(200).json({ uid: decoded.uid });
    } catch (err) {
      if (err instanceof HttpsError) {
        res.status(err.httpErrorCode.status).json({ error: err.code, message: err.message });
      } else {
        logger.error("exportData failed", { err: String(err) });
        res.status(500).json({ error: "internal" });
      }
    }
  },
);
```

`verifyIdToken` error codes worth mapping: `auth/id-token-expired`, `auth/id-token-revoked` (only with `checkRevoked`), `auth/argument-error` (malformed). All map to `unauthenticated` for the client.

iOS sends the header with `let token = try await Auth.auth().currentUser?.getIDToken()` → `request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")`. Prefer `onCall` whenever you control the client — it does this, plus App Check, plus error mapping, for free.

## Revocation and `checkRevoked`

```ts
await getAuth().revokeRefreshTokens(uid);        // all refresh tokens invalid from now
// Existing ID tokens remain valid until expiry (≤ 1 h) UNLESS you verify with checkRevoked:
await getAuth().verifyIdToken(idToken, /* checkRevoked */ true);   // throws auth/id-token-revoked
```

Use `revokeRefreshTokens` when: password/credential changed, account compromised, role downgraded and you need immediate effect, user deleted (implicit). In `onCall` handlers you cannot pass `checkRevoked`; for immediate effect compare `request.auth.token.auth_time` with `(await getAuth().getUser(uid)).tokensValidAfterTime` (RFC3339 string) and throw `unauthenticated` if `auth_time < tokensValidAfterTime`.

Rules cannot check revocation at all — a revoked-but-unexpired token still passes `request.auth != null` for up to an hour. Plan for that window: privileged actions go through callables.

## Anonymous users and linking

- `Auth.auth().signInAnonymously()` on iOS yields a real uid with `sign_in_provider == "anonymous"`. Server sees a normal `request.auth`.
- Linking (`user.link(with: credential)`, e.g. an Apple credential) **keeps the same uid**. Data under `users/{uid}` does not move. The provider claim becomes `apple.com` on the next token.
- Linking fails with `AuthErrorCode.credentialAlreadyInUse` if the Apple account already belongs to another Firebase user. Then the client signs in with that credential and you decide whether to merge the anonymous data — do it in a callable (`mergeAccounts`) that verifies both uids belong to the caller (old uid via the ID token it still holds, new uid via `request.auth`) — never trust two uids in `request.data`.
- Server policy for anonymous callers: cheaper quotas, no purchases, no sharing, no writes to shared collections. Check in callables:

```ts
const { uid, token } = requireAuth(request);
if (token.firebase.sign_in_provider === "anonymous") {
  throw new HttpsError("failed-precondition", "Link your account to continue.");
}
```

- Firebase deletes anonymous accounts unused for 30 days only if you enable auto-cleanup in the console (Authentication → Settings → User actions). The Firestore data is not deleted with them — you need a scheduled cleanup (see `firestore-data-pro` → `references/scheduled-jobs.md`).

## Service-account identity vs user identity

- The Admin SDK inside a function runs as the function's **service account** and bypasses Firestore/Storage rules entirely. Rules are for clients only.
- `onDocumentCreatedWithAuthContext` exposes `event.authType` (`"app_user" | "system" | "service_account" | "unauthenticated" | "unknown"`) and `event.authId`. Use it to skip re-processing writes made by your own functions (`authType === "service_account"`).
- Function-to-function calls over HTTP (`invoker: "private"`) authenticate with a Google-signed OIDC token from the caller's service account, not a Firebase ID token. Do not mix the two: `verifyIdToken` rejects OIDC tokens from service accounts.
- Custom tokens (`getAuth().createCustomToken(uid, claims?)`) mint a sign-in for a uid you assert. Only use them for bridging an external identity system; never return one to an unauthenticated caller based on client-provided data.

## Does not exist / common mistakes

- `(data, context)` handler and `context.auth` — v1 signature. v2 is `(request)` with `request.auth`, `request.data`.
- `firebase-functions/v2/auth` — does not exist. User lifecycle triggers (`auth.user().onCreate` / `.onDelete`) are v1 only (`firebase-functions/v1`); blocking triggers are `firebase-functions/v2/identity` (`beforeUserCreated`, `beforeUserSignedIn`) and need Identity Platform.
- `request.auth.token.roles` as an array with `in` checks in rules — allowed, but arrays bloat the 1000-byte limit fast; prefer one `role` string or a small map.
- `setCustomUserClaims` then reading `request.auth.token.role` in the same callable — the current request's token is already decoded; the new claim shows up only on the next refreshed token.
- Checking `request.auth.token.email_verified` for Apple sign-ins — Apple emails are verified by Apple; Firebase sets `email_verified: true`. For `password` provider it may be `false` and you should gate on it.
- Using `getAuth().getUser(uid)` in every callable "to check the role" — that is a network call per request; the claim in the token is free.
- Verifying an App Check token with `verifyIdToken` — different token, different API (`getAppCheck().verifyToken`).

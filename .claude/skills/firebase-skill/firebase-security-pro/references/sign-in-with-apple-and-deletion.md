# Sign in with Apple and account deletion

Targets Firebase iOS SDK 12.x (`FirebaseAuth`, `AuthenticationServices`), firebase-functions 6.x, firebase-admin 13.x.

## What Apple requires

- **App Store Review Guideline 5.1.1(v)**: an app that supports account creation must let the user **initiate account deletion from within the app**. A link to a website is not enough; a support email is not enough. The flow may include confirmation steps, but it must complete without contacting support.
- **Sign in with Apple**: when the user deletes their account, the app must also **revoke the Sign in with Apple token** via Apple's REST API (`https://appleid.apple.com/auth/revoke`) — Firebase wraps that call as `Auth.auth().revokeToken(withAuthorizationCode:)` (Firebase iOS SDK ≥ 9.x). Without revocation the user keeps seeing the app under Settings → Apple ID → Sign in with Apple, and Apple rejects the build.
- If the app offers Sign in with Apple it is optional to *also* offer other social logins, but any third-party login (Google, Facebook) makes Sign in with Apple **mandatory** (guideline 4.8). Email/password alone does not trigger that.

## Sign in with Apple — client

```swift
import AuthenticationServices
import CryptoKit
import FirebaseAuth

// 1. Nonce: random, hashed for the Apple request, raw for Firebase
let rawNonce = randomNonceString()                       // 32 chars from SecRandomCopyBytes
let hashedNonce = SHA256.hash(data: Data(rawNonce.utf8)).map { String(format: "%02x", $0) }.joined()

let request = ASAuthorizationAppleIDProvider().createRequest()
request.requestedScopes = [.fullName, .email]
request.nonce = hashedNonce

// 2. In the ASAuthorizationControllerDelegate success path:
guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
      let tokenData = appleIDCredential.identityToken,
      let idTokenString = String(data: tokenData, encoding: .utf8),
      let codeData = appleIDCredential.authorizationCode,
      let authCode = String(data: codeData, encoding: .utf8) else { throw AuthFlowError.malformedCredential }

let credential = OAuthProvider.appleCredential(
  withIDToken: idTokenString,
  rawNonce: rawNonce,
  fullName: appleIDCredential.fullName     // Firebase ≥ 10.x: populates displayName on first sign-in
)

// 3a. Fresh sign-in
let result = try await Auth.auth().signIn(with: credential)
// 3b. Or link an anonymous user (same uid is kept)
// let result = try await Auth.auth().currentUser?.link(with: credential)

// 4. Keep `authCode` in memory for this session ONLY if you are about to delete the account
//    (it is single-use and expires in ~5 minutes). Do not persist it.
```

Facts:

- Apple sends `fullName` and `email` **only on the first authorization** for that app/team. Persist the display name to `users/{uid}` in that first sign-in; later sign-ins return `nil`.
- "Hide My Email" gives a `@privaterelay.appleid.com` address. It is a real, verified email; treat it as such and never show "please verify your email".
- `sign_in_provider` in the ID token is `apple.com`.
- Firebase console: Authentication → Sign-in method → Apple must be enabled. For revocation, Firebase also needs the **Services ID, Team ID, Key ID and .p8 private key** configured there (same screen) — without it `revokeToken` fails with an internal error.

## Re-authentication before sensitive actions

Firebase requires a **recent** sign-in for `user.delete()`, `updateEmail`, `updatePassword`. If the last sign-in is too old these throw `AuthErrorCode.requiresRecentLogin`. Rather than catching it, re-authenticate up front when the user taps "Delete account":

```swift
// Run the Apple authorization flow again (new credential + new authorization code), then:
try await Auth.auth().currentUser?.reauthenticate(with: credential)
// Now both `authCode` (fresh) and the session (recent) are valid for deletion.
```

Server-side "recent sign-in" check is `request.auth.token.auth_time` — seconds since epoch of the last sign-in event. Reauthentication updates it.

## Deletion flow (end to end)

Order matters. Revoke Apple first (needs a live Firebase user to call the API), delete data second (needs the uid, done by the server), delete the auth user last (after which nothing can be attributed to the uid).

```
iOS                                   Server (callable deleteAccount)
---                                   ------------------------------
1. Re-authenticate with Apple
2. revokeToken(withAuthorizationCode:)
3. call deleteAccount()   ───────────► 4. verify auth, auth_time recent, not anonymous-with-purchases
                                       5. mark users/{uid}.status = "deleting"  (rules deny further client writes)
                                       6. delete Storage prefixes, Firestore subtree, FCM tokens, external data
                                       7. getAuth().deleteUser(uid)
                          ◄───────────  8. return { ok: true }
9. Auth state listener fires (user == nil) → show signed-out UI
```

### iOS

```swift
func deleteAccount(authCode: String) async throws {
  // Step 2 — only for Apple-linked users
  if Auth.auth().currentUser?.providerData.contains(where: { $0.providerID == "apple.com" }) == true {
    try await Auth.auth().revokeToken(withAuthorizationCode: authCode)
  }
  // Step 3 — server does the deletion so data is never orphaned
  let deleteAccount: Callable<DeleteAccountRequest, DeleteAccountResponse> =
    Functions.functions(region: "asia-southeast1").httpsCallable(
      "deleteAccount",
      options: HTTPSCallableOptions(requireLimitedUseAppCheckTokens: true))
  _ = try await deleteAccount(DeleteAccountRequest(confirm: true))
  // Step 9 — server called deleteUser; local session is now invalid. Clean local state.
  try? Auth.auth().signOut()
}
```

`user.delete()` on the client is an alternative for step 7, but then data deletion depends on a v1 `auth.user().onDelete` trigger or the Delete User Data extension running *after* the fact. The callable is deterministic and testable; prefer it. Inside TCA: an `AccountClient` dependency with `deleteAccount(authCode:)`; the reducer sends `.deleteAccountResponse(Result<Void, Error>)`.

### Server

```ts
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/logger";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getAuth } from "firebase-admin/auth";
import { getStorage } from "firebase-admin/storage";

const RECENT_SIGN_IN_SECONDS = 5 * 60;

export const deleteAccount = onCall(
  { region: "asia-southeast1", enforceAppCheck: true, consumeAppCheckToken: true, timeoutSeconds: 300, maxInstances: 5 },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    const uid = request.auth.uid;
    const authTime = request.auth.token.auth_time;                     // seconds
    if (Date.now() / 1000 - authTime > RECENT_SIGN_IN_SECONDS) {
      throw new HttpsError("failed-precondition", "Please sign in again to delete your account.", { reason: "requires-recent-login" });
    }
    if (request.data?.confirm !== true) throw new HttpsError("invalid-argument", "Confirmation required.");

    const db = getFirestore();
    const userRef = db.doc(`users/${uid}`);
    // 5. Freeze the account so concurrent client writes are rejected by rules (status == 'deleting').
    await userRef.set({ status: "deleting", updatedAt: FieldValue.serverTimestamp() }, { merge: true });

    try {
      // 6a. Storage — every prefix the app writes for this user
      const bucket = getStorage().bucket();
      await bucket.deleteFiles({ prefix: `users/${uid}/`, force: true });
      await bucket.deleteFiles({ prefix: `derived/${uid}/`, force: true });
      // 6b. Firestore — doc + all subcollections (batched internally, BulkWriter under the hood)
      await db.recursiveDelete(userRef);
      // 6c. Top-level docs keyed by uid elsewhere (shares, ledgers) — query and delete in batches
      const shares = await db.collection("shares").where("ownerId", "==", uid).select().get();
      const bw = db.bulkWriter();
      shares.docs.forEach((d) => bw.delete(d.ref));
      await bw.close();
      // 6d. External systems (RevenueCat, Stripe customer, analytics user id) — call their delete APIs here.
      // 7. Auth user last
      await getAuth().deleteUser(uid);
      logger.info("account deleted", { uid });
      return { ok: true };
    } catch (err) {
      logger.error("deleteAccount failed", { uid, err: String(err) });
      // Leave status = "deleting"; a scheduled job retries partial deletions (see firestore-data-pro scheduled-jobs.md).
      throw new HttpsError("internal", "Deletion failed. We will finish removing your data automatically.");
    }
  },
);
```

Rules companion: `allow update: if isOwner(uid) && existing().status != 'deleting' && ...` so the client cannot resurrect data mid-deletion; `allow create` on `users/{uid}` must also be denied while a `deleting` doc exists (it is, because the doc exists and `create` fails on existing docs).

Anonymous users: allow deletion without re-auth (there is nothing to re-auth with), skip the Apple step, but still run the server path — anonymous data is still user data.

## Delete User Data extension

`firebase/delete-user-data` (official extension) listens to Auth user deletion and removes configured Firestore paths (`users/{UID}`, with recursive option), RTDB paths, and Storage paths (`users/{UID}` prefix). It is a reasonable safety net **in addition to** the callable: if anything deletes the auth user by another route (console, Admin script, `user.delete()` from an old app version), the extension cleans up. Configure the same paths the callable deletes. It does not know about top-level collections keyed by a field (`shares.ownerId`) unless you enable its discovery/search mode — verify against the extension's current README before relying on that.

Alternative to the extension: a v1 trigger.

```ts
import * as functionsV1 from "firebase-functions/v1";
export const onUserDeleted = functionsV1.region("asia-southeast1").auth.user().onDelete(async (user) => {
  await getFirestore().recursiveDelete(getFirestore().doc(`users/${user.uid}`));
});
```

This is **v1 only** — there is no `firebase-functions/v2/auth`. Deploy it next to the v2 functions; mixing generations in one codebase is fine.

## Export (data portability)

Pair deletion with an `exportAccount` callable that writes a JSON bundle of the user's docs to `exports/{uid}/{exportId}.json` in a private bucket and returns a 15-minute signed URL. Same auth + recent-sign-in gate. See `secrets-and-pii.md` for what to redact.

## Does not exist / common mistakes

- `Auth.auth().revokeToken(withAuthorizationCode:)` called **after** `user.delete()` — there is no signed-in user any more; the call fails. Revoke first.
- Persisting the Apple `authorizationCode` for later deletion — single-use, ~5 min TTL. Re-run the Apple flow at deletion time.
- Deleting the auth user first and "cleaning up later" with a uid the client sent — after `deleteUser`, `request.auth` for that uid can never exist again; anything the callable did not delete is orphaned unless the extension/trigger runs.
- `firebase-functions/v2/auth` with `onUserDeleted` — does not exist; v1 `auth.user().onDelete` or the v2 `identity` blocking triggers (which have no delete hook).
- Requiring `email_verified` for Apple users — already verified; relay emails are legitimate.
- Treating `requiresRecentLogin` as a bug — it is expected; re-authenticate first.
- Relying on `db.recursiveDelete` for Storage — it is Firestore only. Storage needs `bucket.deleteFiles({ prefix })`.
- Relying on the Delete User Data extension to delete docs found by a field query — verify its configuration; enumerate those collections in the callable.

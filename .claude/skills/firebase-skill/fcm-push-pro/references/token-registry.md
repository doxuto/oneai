# Token registry

The registry is the list of FCM registration tokens the server may send to. Every design decision here serves one goal: at send time, the query `users/{uid}/devices` returns only tokens that can still receive.

## Schema

One document per **installation**, keyed by the Firebase Installations id. A user with three devices has three documents. Reinstalling the app creates a new installation id and a new document; the old one ages out.

```
users/{uid}/devices/{installationId}
  token:       string        // FCM registration token
  platform:    "ios"         // filter on this; the same schema can hold "android" later
  appVersion:  string        // "1.4.2 (312)" — lets you skip devices that cannot handle a new payload
  osVersion:   string        // "iOS 18.1"
  locale:      string        // "vi-VN" — server-side localisation picks strings from this
  timeZone:    string        // "Asia/Ho_Chi_Minh" — quiet hours and digests are computed against this
  updatedAt:   Timestamp     // FieldValue.serverTimestamp() on every launch and every refresh
  createdAt:   Timestamp
```

Do not:

- Store tokens in an array on `users/{uid}` — arrays cannot be timestamped per entry and `arrayRemove` on a stale token races with a refresh.
- Key the document by the token itself — a token refresh would create a second document for the same device and the old one would linger until pruned.
- Store `apnsToken` — the server sends through FCM, which owns the APNs mapping. Only the FCM token matters.

Security rules: the owner may create/update/delete their own device documents, but only with the allowed keys. The server (Admin SDK) bypasses rules.

```
match /users/{uid}/devices/{installationId} {
  allow read, delete: if isOwner(uid);
  allow create, update: if isOwner(uid)
    && request.resource.data.keys().hasOnly(['token','platform','appVersion','osVersion','locale','timeZone','updatedAt','createdAt'])
    && request.resource.data.token is string
    && request.resource.data.platform == 'ios';
}
```

## Upload path (iOS)

Two events write the document: app launch (or foreground) and token refresh. Both go through the same function so the timestamp is always fresh.

```swift
import FirebaseMessaging
import FirebaseInstallations
import FirebaseFirestore
import FirebaseAuth

actor PushRegistrar {
  static let shared = PushRegistrar()
  private var lastUploaded: (uid: String, token: String)?

  /// Call from `didReceiveRegistrationToken` and once per foreground after sign-in.
  func upload(token: String) async throws {
    guard let uid = Auth.auth().currentUser?.uid else { return }       // upload after sign-in; see below
    if lastUploaded?.uid == uid, lastUploaded?.token == token { return } // cheap in-memory dedupe per session
    let installationId = try await Installations.installations().installationID()
    let ref = Firestore.firestore().document("users/\(uid)/devices/\(installationId)")
    try await ref.setData([
      "token": token,
      "platform": "ios",
      "appVersion": Bundle.main.versionString,
      "osVersion": "iOS \(UIDevice.current.systemVersion)",
      "locale": Locale.current.identifier,
      "timeZone": TimeZone.current.identifier,
      "updatedAt": FieldValue.serverTimestamp(),
      "createdAt": FieldValue.serverTimestamp(),   // overwritten only on create — see merge below
    ], merge: true)
    lastUploaded = (uid, token)
  }
}
```

`merge: true` with `createdAt` in every write resets `createdAt`; if you need a true creation time, read the document first or set `createdAt` only in the `didReceiveRegistrationToken` path. Most apps only need `updatedAt`.

Ordering rules the upload depends on:

1. `Messaging.messaging().apnsToken = deviceToken` must be set in `didRegisterForRemoteNotificationsWithDeviceToken` before the FCM token is read. Without an APNs token the FCM token is not usable on iOS.
2. `didReceiveRegistrationToken` fires on every launch (with the same token, usually) and when the token rotates. Treat it as the primary upload hook.
3. On foreground, also call `try await Messaging.messaging().token()` and upload — this covers the case where the delegate fired before the user was signed in.

The in-memory dedupe means one write per session per token; Firestore writes are cheap enough that "one write per launch" is the right trade for a fresh `updatedAt`.

## Refresh on the server

The server never refreshes tokens; it only reads them and deletes bad ones. Query pattern:

```ts
const devices = await db
  .collection(`users/${uid}/devices`)
  .where("platform", "==", "ios")
  .get();
```

No `orderBy`; no index required. If a user somehow has more than 500 devices, chunk the send (see `sending.md`).

## Delete on error

Delete the device document as soon as FCM says the token is dead. Do this in the send path, not in a separate cleanup — the next send would otherwise pay for the same failure again.

```ts
const DEAD = new Set(["messaging/registration-token-not-registered", "messaging/invalid-registration-token"]);

const stale: FirebaseFirestore.DocumentReference[] = [];
res.responses.forEach((r, i) => {
  if (!r.success && DEAD.has(r.error?.code ?? "")) stale.push(deviceDocs[i].ref);
});
if (stale.length) {
  const batch = db.batch();            // ≤ 500 ops per batch; stale.length ≤ chunk size ≤ 500
  stale.forEach((ref) => batch.delete(ref));
  await batch.commit();
}
```

`messaging/invalid-argument` on a token means the string itself is malformed (truncated, wrong field) — a client bug. Log it with the document path and delete the document too; it will never succeed.

## Scheduled prune

Firebase's own guidance: a token not refreshed in 270 days is considered stale by FCM; prune your registry earlier (one to two months) so sends do not waste quota on abandoned devices. Use 60 days.

```ts
import { onSchedule } from "firebase-functions/v2/scheduler";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { logger } from "firebase-functions";

export const pruneStaleDevices = onSchedule(
  { schedule: "every day 03:30", timeZone: "Asia/Ho_Chi_Minh", region: "asia-southeast1", retryCount: 1 },
  async () => {
    const db = getFirestore();
    const cutoff = Timestamp.fromMillis(Date.now() - 60 * 24 * 60 * 60 * 1000);
    let deleted = 0;
    // collectionGroup query needs a single-field index on devices.updatedAt (collection-group scope).
    let last: FirebaseFirestore.QueryDocumentSnapshot | undefined;
    for (;;) {
      let q = db.collectionGroup("devices").where("updatedAt", "<", cutoff).orderBy("updatedAt").limit(400);
      if (last) q = q.startAfter(last);
      const page = await q.get();
      if (page.empty) break;
      const batch = db.batch();
      page.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
      deleted += page.size;
      last = page.docs[page.docs.length - 1];
    }
    logger.info("pruned stale devices", { deleted, cutoff: cutoff.toDate().toISOString() });
  }
);
```

Add to `firestore.indexes.json`:

```json
{ "fieldOverrides": [{ "collectionGroup": "devices", "fieldPath": "updatedAt",
  "indexes": [{ "order": "ASCENDING", "queryScope": "COLLECTION_GROUP" }] }] }
```

Alternative with less code: set a `expiresAt` Timestamp field (= `updatedAt` + 60 days) on every upload and enable a Firestore TTL policy on `devices.expiresAt`. TTL deletes within about 24 hours of expiry and needs no function. Prefer TTL when the 60-day boundary does not need to be exact.

## Multi-device users

- Sending to a user means sending to every document under `users/{uid}/devices`. There is no "primary device".
- Badge counts must be the same on every device: compute the count server-side (unread inbox items) and send it as `aps.badge` to all tokens. Never `FieldValue.increment` a per-device badge.
- Collapse duplicates across devices only via the client (the app marks the item read; a subsequent silent push or the Firestore listener clears the badge elsewhere). APNs `apns-collapse-id` collapses within one device, not across devices.

## Sign-out and account switch

When the user signs out, the device document must not remain under the old uid — otherwise the next user of that phone receives the previous user's pushes.

```swift
func signOut() async throws {
  if let uid = Auth.auth().currentUser?.uid {
    let installationId = try await Installations.installations().installationID()
    try? await Firestore.firestore().document("users/\(uid)/devices/\(installationId)").delete()
  }
  try? await Messaging.messaging().deleteToken()   // forces a fresh token for the next account
  try Auth.auth().signOut()
}
```

Order matters: delete the document while still authenticated (rules require `isOwner`), then delete the token, then sign out. If the delete fails (offline), the token will still be rotated by `deleteToken()` and the old document dies at the next send (`registration-token-not-registered`) or the prune.

On account deletion, the server-side cleanup (v1 `auth.user().onDelete` or the Delete User Data extension) removes `users/{uid}` recursively, which includes `devices`.

## Topic subscriptions and the registry

`subscribeToTopic(tokens, topic)` is a server-side operation; it does not need the registry to be consulted at send time, but it does need the registry to unsubscribe dead tokens. Keep topic membership derivable from user data (e.g. `users/{uid}.plan == "pro"` → topic `pro`) and reconcile in the same scheduled job that prunes, rather than storing topic lists on the device document.

## Does not exist / common mistakes

- `getMessaging().sendToDevice` — removed with the legacy FCM API (June 2024).
- `Messaging.messaging().fcmToken` as a reliable synchronous read at launch — it can be `nil` before the APNs token is set; use the delegate or `try await Messaging.messaging().token()`.
- `Messaging.messaging().apnsToken` set from `Data.description` or a hex string — assign the raw `Data`.
- `arrayUnion(token)` on the user document — see "Do not" above.
- Storing `Installations.installations().installationID()` as the FCM token — they are different values; the installation id is the document key, the FCM token is the field.
- `retryCount` on `onSchedule` retrying a prune that already half-completed — the job is idempotent (deletes are), so retries are safe here.

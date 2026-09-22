# Cloud Storage security rules, signed URLs, and download tokens

Targets `storage.rules` (`rules_version = '2'`), firebase-admin 13.x (`firebase-admin/storage`, backed by `@google-cloud/storage`), Firebase iOS SDK 12.x (`FirebaseStorage`).

## Skeleton (per-user paths, deny by default)

```
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {

    function signedIn() { return request.auth != null; }
    function isOwner(uid) { return signedIn() && request.auth.uid == uid; }
    function isPermanent() { return signedIn() && request.auth.token.firebase.sign_in_provider != 'anonymous'; }
    function isImage() { return request.resource.contentType.matches('image/(jpeg|png|heic|webp)'); }
    function isPdf() { return request.resource.contentType == 'application/pdf'; }
    function underMiB(n) { return request.resource.size < n * 1024 * 1024; }

    // Originals uploaded by the app
    match /users/{uid}/scans/{scanId}/{fileName} {
      allow read: if isOwner(uid);
      allow create: if isOwner(uid) && (isImage() && underMiB(10) || isPdf() && underMiB(25))
        && fileName.matches('^page-[0-9]{1,3}\\.(jpg|png|heic|pdf)$')
        && request.resource.metadata.keys().hasOnly(['scanId', 'pageIndex']);
      allow update: if false;                // overwrite = delete + create, keep it explicit
      allow delete: if isOwner(uid) && isPermanent();
    }

    // Derived files written only by functions (thumbnails, OCR output)
    match /derived/{uid}/{allPaths=**} {
      allow read: if isOwner(uid);
      allow write: if false;
    }

    // Avatar: one fixed name per user
    match /users/{uid}/avatar.jpg {
      allow read: if signedIn();             // visible to other signed-in users
      allow write: if isOwner(uid) && isImage() && underMiB(2);
    }

    match /{allPaths=**} { allow read, write: if false; }
  }
}
```

Storage rules use the same language as Firestore rules but different objects:

- `request.resource` — the object being written: `size` (bytes), `contentType`, `name`, `metadata` (custom metadata map), `md5Hash`.
- `resource` — the existing object (for `read`, `update`, `delete`). `null` on first `create`.
- `request.auth` — same as Firestore: `uid`, `token` with custom claims and `firebase.sign_in_provider`.
- `read` = `get` + `list`; `write` = `create` + `update` + `delete`. `list` allows enumerating a prefix — usually `allow list: if false` and let the app know its paths from Firestore.

## Size and content-type limits

- `request.resource.size` is the only place you can cap upload size before the bytes are stored. Firestore rules cannot help here.
- `contentType` is **client-declared**. A rule that requires `image/jpeg` stops accidental uploads, not a hostile client renaming a binary. The function that processes the file must sniff magic bytes or let `sharp` reject non-images (`storage-triggers.md` in `firestore-data-pro`).
- Reject `contentType` absent: `request.resource.contentType != null && ...`. The iOS SDK sets it from `StorageMetadata.contentType`; if the app forgets, the object is `application/octet-stream`.
- Path shape is a security control: `fileName.matches(...)` prevents `../` style tricks (not possible in GCS keys anyway) and keeps the trigger's path parser simple.

## Custom metadata

The client can set `StorageMetadata.customMetadata` (Swift) — a `[String: String]`. Constrain it with `request.resource.metadata.keys().hasOnly([...])` and treat values as untrusted input in triggers. Do not put authorization data in metadata. Functions can set metadata on derived files (`file.setMetadata({ metadata: { ownerUid: uid, source: "ocr" } })`) — clients cannot forge that since `write` is denied on `/derived`.

## Admin SDK: bypass, signed URLs, download tokens

Inside functions:

```ts
import { getStorage } from "firebase-admin/storage";

const bucket = getStorage().bucket();                         // default bucket
const file = bucket.file(`users/${uid}/scans/${scanId}/page-1.jpg`);

// Read/write — rules do not apply to the Admin SDK.
const [buffer] = await file.download();
await bucket.file(`derived/${uid}/${scanId}/thumb.jpg`).save(thumb, {
  contentType: "image/jpeg",
  metadata: { metadata: { ownerUid: uid, source: "thumbnail" } },   // nested `metadata` = custom metadata
});
```

### Signed URLs (`getSignedUrl`)

A V4 signed URL grants time-limited access to one object to anyone holding the URL, with no Firebase auth. Generate it on the server, return it from a callable, and keep the expiry short.

```ts
const [url] = await file.getSignedUrl({
  version: "v4",
  action: "read",                       // "read" | "write" | "delete" | "resumable"
  expires: Date.now() + 15 * 60 * 1000, // 15 minutes
  // For "write": contentType: "image/jpeg" — the uploader must send the same header.
});
return { url };   // from an onCall handler; ISO expiry alongside if the client needs it
```

Requirements and gotchas:

- Signing requires the function's service account to have `iam.serviceAccounts.signBlob` (role **Service Account Token Creator** on itself). On Cloud Functions v2 the default compute service account needs that role granted once; otherwise `getSignedUrl` throws `Permission 'iam.serviceAccounts.signBlob' denied`. Alternatively initialise the Admin SDK with a service-account JSON that has a private key (not recommended for functions).
- Max expiry for V4 is 7 days. For a "share this scan" feature use a short-lived URL regenerated per open, not a week-long link stored in Firestore.
- Signed URLs bypass rules and App Check. Log who requested one (uid, object path) and rate-limit the callable.
- Use `action: "write"` signed URLs when a non-Firebase uploader (web widget, partner) needs to upload without a Firebase account. The iOS app should upload with the Firebase SDK instead so rules apply.

### Download tokens (Firebase-specific)

`downloadURL()` on iOS / `getDownloadURL()` on web return `https://firebasestorage.googleapis.com/v0/b/<bucket>/o/<path>?alt=media&token=<uuid>`. The token lives in the object's metadata (`firebaseStorageDownloadTokens`) and **never expires** until revoked; it also bypasses rules for that object.

- Never store a download URL in a document other users can read unless the file is meant to be public to them.
- Revoke by deleting the `firebaseStorageDownloadTokens` metadata key from the Admin SDK: `await file.setMetadata({ metadata: { firebaseStorageDownloadTokens: null } })` — verify against firebase docs; the SDK-side name is `firebaseStorageDownloadTokens`.
- Prefer letting the iOS app read through the SDK (`storageRef.data(maxSize:)` / `getData`) so rules + App Check apply, and reserve download tokens for images loaded by a third-party image library that only takes a URL. For those, a short-lived signed URL from a callable is the safer trade.

## iOS client half

```swift
import FirebaseStorage

let ref = Storage.storage().reference(withPath: "users/\(uid)/scans/\(scanId)/page-1.jpg")
let meta = StorageMetadata()
meta.contentType = "image/jpeg"                    // rules check this
meta.customMetadata = ["scanId": scanId, "pageIndex": "1"]
_ = try await ref.putDataAsync(jpegData, metadata: meta)

// Read through the SDK so rules and App Check apply:
let data = try await ref.data(maxSize: 10 * 1024 * 1024)
```

`putDataAsync` and `data(maxSize:)` are the async APIs in Firebase iOS 9+; on a physical device against the emulator use the Mac's LAN IP. Wrap `Storage` in a `@DependencyClient` (`tca-pro` → `references/dependencies.md`).

## Multiple buckets and regions

- Storage rules are deployed per bucket: `firebase.json` → `"storage": [{ "bucket": "my-project.appspot.com", "rules": "storage.rules" }]` (array form for several buckets). `firebase deploy --only storage`.
- Keep the bucket in the same region as the functions that process it (`asia-southeast1`); `onObjectFinalized` must be deployed in a region that supports the bucket's location.
- A separate bucket with `allow read, write: if false` plus signed URLs is the right shape for exports/backups.

## Testing

`@firebase/rules-unit-testing` 4.x also covers Storage: `initializeTestEnvironment({ projectId: "demo-x", storage: { rules: readFileSync("storage.rules", "utf8"), host: "127.0.0.1", port: 9199 } })` then `env.authenticatedContext("alice").storage()` with the modular web SDK (`uploadBytes`, `getBytes`). Test: owner upload OK, other user denied, oversized denied, wrong content type denied, `/derived` write denied. See `firebase-testing-pro`.

## Does not exist / common mistakes

- `request.resource.data` in storage rules — that is Firestore. Storage has `request.resource.size`, `.contentType`, `.metadata`, `.name`.
- `resource.size` on `create` — `resource` is null on create; use `request.resource`.
- Trusting `contentType` as proof the bytes are an image — sniff on the server.
- `allow read: if true` on avatars "because URLs are unguessable" — GCS object names are enumerable if `list` is ever allowed and are visible in Firestore docs. Require `signedIn()` at least.
- Returning `getSignedUrl` output from a callable with a 7-day expiry stored in Firestore — a leaked doc is a leaked file for a week. Generate per request, short-lived.
- `getSignedUrl` failing with `signBlob` permission — grant Service Account Token Creator to the function's runtime service account; do not embed a service-account key file in the function.
- `match /users/{uid}/{allPaths=**} { allow write: if isOwner(uid) }` — lets the client write into any future subpath including ones functions use for derived output; enumerate prefixes and route function output to a separate top-level prefix.

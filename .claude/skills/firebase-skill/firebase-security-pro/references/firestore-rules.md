# Firestore security rules

Targets `rules_version = '2'`, Cloud Firestore in Native mode. Rules govern **client SDK** access only; the Admin SDK inside Cloud Functions bypasses them entirely.

## Skeleton (deny by default)

```
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // ---- helpers -------------------------------------------------------
    function signedIn() { return request.auth != null; }
    function isOwner(uid) { return signedIn() && request.auth.uid == uid; }
    function hasRole(r) { return signedIn() && request.auth.token.role == r; }
    function isAnonymous() { return signedIn() && request.auth.token.firebase.sign_in_provider == 'anonymous'; }
    function isPermanent() { return signedIn() && !isAnonymous(); }
    function incoming() { return request.resource.data; }
    function existing() { return resource.data; }
    function changedKeys() { return incoming().diff(existing()).affectedKeys(); }
    function isServerTime(field) { return incoming()[field] == request.time; }

    // ---- paths ---------------------------------------------------------
    match /users/{uid} {
      allow get: if isOwner(uid) || hasRole('admin');
      allow list: if hasRole('admin');
      allow create: if isOwner(uid)
        && incoming().keys().hasOnly(['displayName', 'locale', 'schemaVersion', 'createdAt', 'updatedAt'])
        && incoming().displayName is string && incoming().displayName.size() <= 60
        && incoming().schemaVersion == 1
        && isServerTime('createdAt') && isServerTime('updatedAt');
      allow update: if isOwner(uid)
        && !changedKeys().hasAny(['plan', 'role', 'credits', 'createdAt', 'schemaVersion'])
        && isServerTime('updatedAt')
        && incoming().displayName is string && incoming().displayName.size() <= 60;
      allow delete: if false;   // deletion goes through the deleteAccount callable

      match /notes/{noteId} {
        allow read: if isOwner(uid);
        allow create: if isOwner(uid) && validNote() && isServerTime('createdAt');
        allow update: if isOwner(uid) && validNote() && !changedKeys().hasAny(['createdAt', 'ownerId']);
        allow delete: if isOwner(uid) && isPermanent();
      }

      match /devices/{installationId} {
        allow read, write: if isOwner(uid);   // FCM token docs written by the app
      }
    }

    function validNote() {
      let d = request.resource.data;
      return d.keys().hasOnly(['title', 'body', 'tags', 'ownerId', 'isDeleted', 'createdAt', 'updatedAt', 'schemaVersion'])
        && d.keys().hasAll(['title', 'ownerId', 'createdAt', 'updatedAt'])
        && d.title is string && d.title.size() > 0 && d.title.size() <= 200
        && (!('body' in d) || (d.body is string && d.body.size() <= 20000))
        && (!('tags' in d) || (d.tags is list && d.tags.size() <= 10))
        && d.ownerId == request.auth.uid
        && d.updatedAt == request.time;
    }

    match /{document=**} { allow read, write: if false; }
  }
}
```

Order matters only for overlapping matches: when several `match` blocks apply, access is granted if **any** of them allows it. The trailing `/{document=**}` deny is therefore documentation plus protection for paths you forgot — it cannot revoke a permissive rule above it.

## Operations

`read` = `get` + `list`. `write` = `create` + `update` + `delete`. Split them: listing a collection and reading one doc are different threats (enumeration), and `create` needs `request.resource` validation while `delete` needs `resource`.

Variables:

- `request.auth` — `null` or `{ uid, token }`. `token` has `email`, `email_verified`, `phone_number`, `name`, `sub`, `firebase.sign_in_provider`, `firebase.identities`, plus custom claims.
- `request.resource.data` — the document **as it will be after the write** (for `update`, the merged result, not the patch).
- `resource.data` — the current document. Absent on `create`.
- `request.time` — server timestamp of the request. `incoming().createdAt == request.time` is the only way to enforce a client used `FieldValue.serverTimestamp()`.
- `request.method`, `request.path`, `request.query` (`limit`, `offset`, `orderBy`).

## Owner pattern

Owner means the uid in the path or in the doc, never a field the client sends elsewhere. Prefer `users/{uid}/…` paths (the check is a path compare) over top-level collections with an `ownerId` field (the check needs `resource.data.ownerId`, i.e. a document read for every `get`, and every query must filter on it — see "Rules are not filters").

Top-level variant when you need cross-user queries:

```
match /notes/{noteId} {
  allow get: if isOwner(resource.data.ownerId) || resource.data.visibility == 'public';
  allow list: if signedIn();                       // combined with the query constraint below
  allow create: if isOwner(incoming().ownerId) && validNote();
  allow update, delete: if isOwner(existing().ownerId);
}
```

## Role pattern

```
function hasAnyRole(roles) { return signedIn() && request.auth.token.role in roles; }
match /admin/{doc=**} { allow read, write: if hasRole('admin'); }
match /orgs/{orgId}/{doc=**} { allow read: if signedIn() && request.auth.token.orgId == orgId; }
```

Roles come from custom claims (`auth-in-functions.md`). Reading a role from `get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role` works but costs one read per evaluation, and the client could have written that field unless `update` rules forbid it. Claims are cheaper and cannot be forged.

## Field allow-lists and immutable fields

- `keys().hasOnly([...])` on `create`/`update` rejects unknown fields (typo, injection, future privileged field).
- `keys().hasAll([...])` enforces required fields.
- `diff().affectedKeys()` returns the set of keys that changed between `resource.data` and `request.resource.data`. `hasAny([...])` forbids touching them; `hasOnly([...])` restricts an update to a known subset (e.g. `changedKeys().hasOnly(['lastSeenAt'])` for a heartbeat).
- Immutable fields: `!changedKeys().hasAny(['createdAt', 'ownerId', 'schemaVersion'])`.
- Server-only fields: forbid in `create` via `hasOnly` (omit them) and in `update` via `hasAny`. The function sets them with the Admin SDK.

## Type and size validation

```
d.title is string && d.title.size() <= 200
d.count is int && d.count >= 0
d.price is number                          // int or float
d.tags is list && d.tags.size() <= 10 && d.tags.hasOnly(['work', 'home', 'idea'])   // controlled vocabulary
d.meta is map && d.meta.keys().size() <= 20
d.createdAt is timestamp
d.location is latlng
d.email.matches('^[^@]+@[^@]+$')
d.status in ['draft', 'published']
```

Firestore already caps documents at 1 MiB, but rules are where you cap *user-controlled* strings so a single note cannot be a 1 MiB blob. `size()` on a string is characters, on a list/map is element count.

## Timestamps

```
allow create: if incoming().createdAt == request.time && incoming().updatedAt == request.time;
allow update: if incoming().updatedAt == request.time && incoming().createdAt == existing().createdAt;
```

Only `FieldValue.serverTimestamp()` satisfies `== request.time`. A client-supplied `Timestamp(date: .now)` fails, which is what you want. Do not accept `request.time - duration.value(1, 'm') < d.createdAt` "for clock skew" — it just lets the client lie by a minute.

## Anonymous restrictions

```
// Anonymous users: read own data, create with a smaller body cap, no delete, no sharing.
match /users/{uid}/notes/{noteId} {
  allow create: if isOwner(uid) && validNote()
    && (isPermanent() || incoming().body.size() <= 2000);
  allow delete: if isOwner(uid) && isPermanent();
}
match /shares/{shareId} {
  allow create: if isPermanent() && incoming().ownerId == request.auth.uid;
}
```

`request.auth.token.firebase.sign_in_provider == 'anonymous'` is the only reliable signal. Do not rely on the absence of `email`. Rules cannot count documents, so "max N notes for anonymous users" is a callable/quota concern (`rate-limiting-and-abuse.md`), not a rule.

## Collection group rules

A `collectionGroup('notes')` query needs a rule that matches the group path, and it must be provable for **every** document in the group:

```
match /{path=**}/notes/{noteId} {
  allow read: if signedIn() && resource.data.ownerId == request.auth.uid;
}
```

The client query must then be `collectionGroup('notes').where('ownerId', '==', uid)` — a group query without that filter is rejected because the rule cannot be proven for all results. The subcollection docs need `ownerId` stored on them (denormalised from the path) precisely so this rule can be written. Also needs a collection-group index (`firestore.indexes.json`, `queryScope: "COLLECTION_GROUP"` — see `firestore-data-pro` → `references/queries-and-indexes.md`).

## Rules are not filters

A `list` rule is evaluated against the **query**, not against each returned document. `allow list: if resource.data.ownerId == request.auth.uid` accepts a query only if Firestore can prove every possible result satisfies it — i.e. the query contains `.where('ownerId', '==', request.auth.uid)`. A query without that clause fails with `permission-denied` even if all documents happen to belong to the user.

Consequences:

- Every "my stuff" list on iOS carries the `where` clause. Write the rule and the query together.
- `request.query.limit <= 100` in the `list` rule caps enumeration and forces the client to paginate.
- `orderBy` on a field the rule constrains with `==` is fine; range filters on other fields are fine; `!=`/`not-in` on the constrained field is not provable.

## Rules for callables-only collections

Collections written only by functions (quota docs, ledgers, `admin/*`, `_meta/*`) get `allow read, write: if false;` or read-only for the owner. The Admin SDK does not need permission.

```
match /users/{uid}/quota/{key} { allow read: if isOwner(uid); allow write: if false; }
match /events/{eventId} { allow read, write: if false; }   // idempotency ledger
```

## Evaluation limits

- Max 10 `get()`/`exists()` calls per single-document request, 20 for multi-document (queries/transactions). Each is a billed read.
- Rules have a size limit (256 KB source) and a nesting/expression complexity limit; split helpers, avoid deep recursion.
- Deploy: `firebase deploy --only firestore:rules`. Rules take effect within about a minute; old app versions keep working only if the rules still allow their writes — add fields as optional first.

## Testing

Unit-test rules with `@firebase/rules-unit-testing` 4.x against the emulator: `assertSucceeds` / `assertFails` per operation, per principal (signed-out, anonymous, owner, other user, admin). Use a `demo-` project id. Full harness and CI wiring: `firebase-testing-pro` → `references/rules-testing.md`. Write one test per `allow` line; a rule without a failing test for the *other* user is untested.

## Does not exist / common mistakes

- `allow read, write: if request.auth.uid != null;` — the classic "authenticated users can do anything". Every user can read and delete every other user's data.
- `allow read: if true` "because App Check is enforced" — App Check does not identify users; the data is public to all app users.
- `request.resource.data` on `delete` — undefined; use `resource.data`.
- Using `request.resource.data` on `update` as if it were the patch — it is the merged document; `hasOnly` on it checks the whole doc, `diff()` is how you inspect the change.
- `request.auth.token.admin == true` with the claim set from the client via `updateProfile` — clients cannot set claims; but check that no callable sets claims from `request.data`.
- `resource.data.ownerId == request.auth.uid` in a `list` rule with a query that lacks the matching `where` — fails at runtime, works in the rules playground for single docs.
- Relying on rules for revocation — a revoked but unexpired ID token passes `request.auth != null` for up to 1 hour.
- Missing the trailing deny — a new top-level collection created by a function becomes readable by nobody (fine) but a typo path like `/user/{uid}` created by the client is denied only if the catch-all exists.
- `match /users/{uid}/{document=**}` giving owners recursive access, then adding `users/{uid}/quota` later — the recursive wildcard already grants the client write on it. Recursive wildcards on user roots are a maintenance trap; enumerate subcollections.

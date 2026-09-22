# Firestore streams

`cloud_firestore` 6.10.0. Firestore is the app's realtime channel: the server writes, the app observes. This file covers typed streams, query and index failures, pagination, offline behaviour, listener lifecycle and cost. Data modelling, rules, and index definitions are `firebase-skill` → `firestore-data-pro` and `firebase-security-pro`.

## `snapshots()` is the channel

```dart
Stream<QuerySnapshot<T>> snapshots({
  bool includeMetadataChanges = false,
  ListenSource source = ListenSource.defaultSource,
});
```

| Parameter | Effect |
|---|---|
| `includeMetadataChanges: false` (default) | Emits only when document data changes |
| `includeMetadataChanges: true` | Also emits when `hasPendingWrites` or `isFromCache` flips — needed for "saving…" indicators |
| `ListenSource.defaultSource` | Cache first, then server updates |
| `ListenSource.cache` | Cache only; an empty cache yields an empty snapshot and no server traffic |

One listener per logical screen. A listener is a long-lived server connection: it bills one document read per document delivered, both on the first snapshot and on every later change, and it keeps a socket alive while it is attached.

## Typed documents with `withConverter`

```dart
typedef FromFirestore<T> = T Function(
  DocumentSnapshot<Map<String, dynamic>> snapshot,
  SnapshotOptions? options,
);
```

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

```dart
final class Note {
  const Note({required this.id, required this.title, required this.updatedAt});

  factory Note.fromFirestore(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data()!;              // only called for existing docs
    return Note(
      id: snapshot.id,
      title: data['title'] as String? ?? '',
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  final String id;
  final String title;
  final DateTime updatedAt;

  Map<String, Object?> toFirestore() => {
        'title': title,
        'updatedAt': FieldValue.serverTimestamp(),
      };
}
```

- `withConverter` returns a new `CollectionReference<T>`/`Query<T>`; it does not mutate the original. Apply it before `orderBy`/`where`/`limit` and the whole chain stays typed.
- Inside `fromFirestore`, documents **do** contain `Timestamp`, `DocumentReference` and `GeoPoint`. That is the difference from a callable: this is the Firestore wire format, not JSON. Convert `Timestamp` to `DateTime` here and let nothing above the converter see it.
- Write `FieldValue.serverTimestamp()` rather than a client `DateTime`; a device with a wrong clock otherwise reorders the list for everyone.
- `snapshot.data()` returns `T?` on a `DocumentSnapshot<T>`; it is null when the document does not exist. In `fromFirestore` the snapshot is always an existing document, so `!` is safe there and nowhere else.
- A converter that throws takes the whole stream down with an error. Decode defensively (`as String? ?? ''`) for fields the server may add later.

## Queries and the index error

Firestore rejects a composite query with no matching index at runtime, not at compile time, and only on the first execution:

```
[cloud_firestore/failed-precondition] The query requires an index. You can create it here: https://console.firebase.google.com/...
```

It surfaces as a `FirebaseException` with `plugin: 'cloud_firestore'` and `code: 'failed-precondition'`, on the stream's error channel — so an `AsyncError` in a `StreamProvider`, not a thrown exception at the call site.

- The message contains a console URL that creates the exact index. Follow it once, then commit the generated entry to `firestore.indexes.json` so it survives a project rebuild; deployment is `firebase-skill` → `firebase-deploy-pro`.
- Reproduce these in the emulator or in a dev project before release. A query that only runs on a rarely used filter combination ships broken.
- Any query that combines an inequality or a range with an `orderBy` on a different field, or several `where` clauses on different fields, needs a composite index. A single-field equality plus `orderBy` on the same field does not.
- `whereIn` and `arrayContainsAny` are capped (30 values at the time of writing — verify against the Firestore docs for your version) and throw at call time, not on the stream.

## Pagination

Cursor-based, with the cursor being the last `DocumentSnapshot` of the previous page:

```dart
final class NotesPage {
  const NotesPage({required this.notes, required this.lastDoc});
  final List<Note> notes;
  final QueryDocumentSnapshot<Note>? lastDoc;
}

Future<NotesPage> fetchPage({QueryDocumentSnapshot<Note>? after, int limit = 20}) async {
  var query = notesRef.orderBy('updatedAt', descending: true).limit(limit);
  if (after != null) query = query.startAfterDocument(after);

  final snapshot = await query.get();
  return NotesPage(
    notes: [for (final doc in snapshot.docs) doc.data()],
    lastDoc: snapshot.docs.isEmpty ? null : snapshot.docs.last,
  );
}
```

- `startAfterDocument(DocumentSnapshot)` needs every `orderBy` field to be present on that document, and the same `orderBy` chain on the follow-up query. Changing the sort invalidates the cursor.
- `startAfter(List<Object?> values)` takes raw field values instead, for when the cursor has to survive a process restart. Keep the value list in the same order as the `orderBy` clauses.
- Never paginate with `offset`-style skipping. Firestore bills every skipped document and the page drifts under concurrent writes.
- Paginate with `get()`, not `snapshots()`. A listener per page multiplies the socket count and re-delivers old pages on every change. Use a listener for the live head of the list and `get()` for history if you need both.
- A paginated *callable* uses the opaque string cursor the server defines — that is a different mechanism, documented in `firebase-skill` → `firebase-ios-contract` → `references/envelope-and-naming.md`. Do not mix the two in one screen.

## Offline, metadata and pending writes

Persistence is on by default on Android and iOS. That has consequences the UI must show rather than hide:

```dart
Stream<SaveState> watchNote(String id) => notesRef
    .doc(id)
    .snapshots(includeMetadataChanges: true)
    .map((snap) => SaveState(
          note: snap.data(),
          isSaving: snap.metadata.hasPendingWrites,
          isStale: snap.metadata.isFromCache,
        ));
```

| Flag | Meaning |
|---|---|
| `metadata.hasPendingWrites` | This snapshot includes a local write not yet acknowledged by the server |
| `metadata.isFromCache` | This snapshot came from the cache, not from a guaranteed-fresh server read |

- A `set`/`update` resolves its `Future` only when the server acknowledges it. Offline, that `Future` never completes — it does not throw. Never `await` a Firestore write to drive a progress spinner; write, then let the local snapshot with `hasPendingWrites == true` drive the UI.
- Two snapshots arrive for a local write: the optimistic one (`hasPendingWrites: true`) and the confirmed one. Without `includeMetadataChanges: true` you only see the data change, so a "saved" tick never appears.
- `Settings(persistenceEnabled: false, cacheSizeBytes: ...)` is set once, before any Firestore use: `FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);`. Changing it after the first read has no effect.
- `clearPersistence()` only works before Firestore is started or after `terminate()`. It is a sign-out tool, not a refresh button.

## Listener lifecycle

- Inside a Riverpod provider, return the stream and let the provider own it. Auto-dispose cancels the underlying subscription when the last listener goes away; see `riverpod-integration.md` and `riverpod-pro`.
- Outside a provider, every `.listen(...)` produces a `StreamSubscription` that must be cancelled in `dispose`. A leaked listener keeps billing and keeps a reference to a disposed `State`.
- Signing out while listeners are attached produces a burst of `permission-denied` errors from rules. Cancel the user-scoped listeners first, then sign out — in Riverpod, invalidate the user-scoped providers as part of the sign-out flow.
- Never open a listener from `build()` of a widget. It re-subscribes on every rebuild.
- Do not recreate the query object on every rebuild either: `collection(...).where(...)` builds a new `Query` each time, and a `StreamBuilder` whose `stream:` expression is rebuilt tears down and re-establishes the listener, re-reading every document.

## Long jobs: status document + listener

The pattern the server skill describes in `firebase-skill` → `firebase-ios-contract` → `references/realtime-vs-callable.md`. A callable enqueues work and returns a `jobId`; a task worker writes progress to `users/{uid}/jobs/{jobId}`; the app listens.

```dart
Future<String> startScan(String storagePath) async {
  final res = await _startScan.call<Map<String, dynamic>>({'storagePath': storagePath});
  return res.data['jobId'] as String;
}

Stream<Job> watchJob(String jobId) => _firestore
    .doc('users/$uid/jobs/$jobId')
    .withConverter<Job>(
      fromFirestore: (snap, _) => Job.fromFirestore(snap),
      toFirestore: (job, _) => job.toFirestore(),
    )
    .snapshots()
    .map((snap) => snap.data() ?? Job.missing(jobId));
```

Why this and not a long callable:

| | Long callable | Status document |
|---|---|---|
| Duration cap | Server `timeoutSeconds` and client `timeout` | None |
| App backgrounded | Request dies | Resumes on reconnect |
| Progress | None (or a stream that dies with the app) | Every write is a progress event |
| Two devices | Only the caller sees it | Both see it |
| Retry | Client re-runs the whole job | Cloud Tasks retries server-side |

`Job.status` is a tolerant enum (`queued`, `processing`, `done`, `failed`, `unknown`) — see `models-and-serialization.md`. Handle the missing-document case explicitly: rules may deny it, or the job may not exist, and `snapshot.data()` is then `null`.

## Does not exist / common mistakes

- Polling a callable on a `Timer` for progress — costs, latency and battery; use a listener.
- `await docRef.set(...)` to know a write succeeded — offline it never completes. Use `hasPendingWrites`.
- `snapshots()` without `includeMetadataChanges: true` while showing a "saving…" indicator — the metadata flip never arrives.
- `snapshot.data()!` on an arbitrary document — null when the document does not exist or rules denied it.
- Passing a Firestore `Timestamp` out of the converter into the domain layer — convert to `DateTime` at the boundary.
- A client `DateTime.now()` written as `updatedAt` — use `FieldValue.serverTimestamp()`.
- `enablePersistence()` — no longer on `FirebaseFirestore` in cloud_firestore 6.x (it was the web-only API). Persistence is on by default on Android and iOS and is configured through `Settings`.
- `Settings(cache: ...)` — the Dart `Settings` constructor takes `persistenceEnabled` and `cacheSizeBytes`, not a cache-settings object.
- A `StreamBuilder` whose `stream:` argument is a fresh `query.snapshots()` expression — re-subscribes and re-reads on every rebuild. Hold the stream in a provider or a field.
- `.limit()` omitted on a collection listener — the first snapshot reads the entire collection.
- Ignoring the console URL in a `failed-precondition` index error and switching the query to client-side filtering — downloads the whole collection to filter three documents.

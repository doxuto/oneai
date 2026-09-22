---
name: flutter-firebase-contract
description: Writes, reviews, and keeps in sync the Flutter half of the API contract between Firebase Cloud Functions and a Flutter app. Use when reading, writing, or reviewing code that uses FirebaseFunctions.instanceFor, httpsCallable, HttpsCallableOptions, HttpsCallableResult, FirebaseFunctionsException, StreamResponse, snapshots(), withConverter, FirebaseAppCheck.activate, FirebaseMessaging.onBackgroundMessage, firebase_options.dart, or useFunctionsEmulator, or when the user mentions callable contract, error mapping, Firestore listeners, FCM tokens, App Check, or running Flutter against the Firebase emulator suite.
license: MIT
metadata:
  author: doxuto
  version: "1.0"
  targets: "firebase_core 4.15.0, cloud_functions 6.5.0, cloud_firestore 6.10.0, firebase_auth 6.7.0, firebase_messaging 16.7.0, firebase_app_check 0.4.8, flutter_riverpod 3.4.3, Flutter 3.47.5, Dart 3.13.4"
---

Define and review the Dart side of the contract with a Firebase backend so that the app decodes exactly what the server encodes, every server error becomes a typed Dart failure the UI can switch on, and Firebase types never leak past the repository layer. The server is the source of truth for the wire format; this skill describes the half that consumes it. Report only genuine problems — do not nitpick or invent issues.

## Core principles

1. **One shape, two languages.** The zod schema on the server and the Dart model in the app describe the same JSON. Field names, optionality, and enum strings are identical; only the syntax differs. Anything server-side — the schema itself, `HttpsError` choice, rules, indexes — belongs to `firebase-skill` → `firebase-functions-pro`, `firebase-security-pro`, `firestore-data-pro`.
2. **JSON on the wire, nothing else.** Strings, numbers, booleans, null, lists, maps. Dates are ISO-8601 strings parsed with `DateTime.parse`. Firestore `Timestamp`, `DocumentReference`, and `GeoPoint` never cross a callable boundary in either direction.
3. **`HttpsCallableResult<T>.data` is an unchecked cast.** `call<T>()` hands the platform-channel value straight to `HttpsCallableResult<T>` with no validation. Always `call<Map<String, dynamic>>()` and then run your own `fromJson`; `call<MyModel>()` compiles and throws `TypeError` at runtime.
4. **Errors are typed on both sides.** Every `HttpsError` code the server throws arrives as a lowercase hyphenated string in `FirebaseFunctionsException.code`. Map it once, at the repository boundary, to a sealed Dart failure with a retry policy and a UX decision. Widgets never see `FirebaseFunctionsException`.
5. **Additive evolution only.** A shipped build calls the deployed function name with the deployed shape. Add optional fields; never rename, remove, or retype in place. Breaking changes get a new function name (`createNoteV2`).
6. **The app talks to a repository, not to Firebase.** Only the repository implementation imports `cloud_functions` and `cloud_firestore`. It is exposed as a Riverpod provider and overridden with a fake in tests. Riverpod mechanics belong to `riverpod-pro`.
7. **Request/response for answers, `snapshots()` for progress.** A callable returns within seconds. Anything longer writes a status document and the app listens to it.

## Review process

1. Check `flutterfire configure` output, `firebase_options.dart`, initialisation order in `main()`, flavours, and the plugin version matrix using `references/setup.md`.
2. Check `FirebaseFunctions.instanceFor`, `httpsCallable`, `HttpsCallableOptions`, typed wrappers, `result.data` handling, and streaming using `references/callables.md`.
3. Check Dart models against the server schema — field names, ISO-8601 dates, enums, nullability, codegen choice — using `references/models-and-serialization.md`.
4. Check the `FirebaseFunctionsException` → sealed failure mapping, `details` decoding, and retry policy using `references/error-mapping.md`.
5. Check `snapshots()`, `withConverter`, query/index errors, pagination, offline metadata, and listener lifecycle using `references/firestore-streams.md`.
6. Check the repository interface, its Riverpod providers, `AsyncValue.guard`, and test overrides using `references/riverpod-integration.md`.
7. Check `firebase_auth` stream choice, forced token refresh, anonymous linking, and `FirebaseAppCheck.activate` providers using `references/auth-and-appcheck.md`.
8. Check FCM permission, token registration, background handler requirements, and notification taps using `references/messaging.md`.
9. Check emulator wiring per platform, seeding, and what is faked versus what is run against the emulator suite using `references/emulators-and-testing.md`.

If doing a partial review, load only the relevant reference files.

## Core instructions

- Import Material from `package:material_ui/material_ui.dart` and Cupertino from `package:cupertino_ui/cupertino_ui.dart`. Flutter 3.47 decoupled both out of the SDK; `package:flutter/material.dart` still compiles but its classes are *distinct types* from the package's, so mixing the two produces "argument type X is not the type X" errors. Migrate with `dart fix --apply --code=migrate_design_widgets`. See `flutter-widgets-pro` → `references/material3-theming.md`.
- Target `firebase_core: ^4.15.0`, `cloud_functions: ^6.5.0`, `cloud_firestore: ^6.10.0`, `firebase_auth: ^6.7.0`, `firebase_messaging: ^16.7.0`, `firebase_app_check: ^0.4.8`. All of them require `firebase_core ^4.14.0` or newer — bump the whole set together, never one plugin alone.
- `main()` is `WidgetsFlutterBinding.ensureInitialized()`, then `await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`, then App Check activation, then emulator wiring, then `runApp`. Any `FirebaseFunctions` or `FirebaseFirestore` instance created before `initializeApp` completes throws.
- Never hand-write `firebase_options.dart`. It is generated by `flutterfire configure`; regenerate it when a platform, bundle id, or project changes. One generated file per flavour via `--out`, not one file with `if (flavor == ...)` branches.
- Get the instance with `FirebaseFunctions.instanceFor(region: 'asia-southeast1')`, matching the server's `setGlobalOptions({ region })`. `FirebaseFunctions.instance` is `us-central1`; a mismatch is `not-found` on every call.
- One `HttpsCallable` per operation, created once in the repository. Function names are camelCase verbs identical to the server export (`createNote`, `listNotes`) — never dotted, never built by string concatenation.
- `HttpsCallableOptions` has exactly three fields: `timeout` (default `Duration(seconds: 60)`), `limitedUseAppCheckToken` (default `false`), and `webAbortSignal` (web only). Set `limitedUseAppCheckToken: true` only on callables the server declares with `consumeAppCheckToken: true`.
- Call as `await callable.call<Map<String, dynamic>>(request.toJson())`, then `Response.fromJson(result.data)`. Treat every nested `List` as `List<dynamic>` (`(json['tags'] as List).cast<String>()`) and every number as `num` (`(json['score'] as num).toDouble()`), because a JSON `1` decodes to `int` and `1.0` to `double`.
- Dates cross as ISO-8601 strings: `DateTime.parse(json['createdAt'] as String)` in, `date.toUtc().toIso8601String()` out. Never send a Firestore `Timestamp` into a callable and never expect one back; `Timestamp` is only for documents read through `snapshots()`.
- Response enums decode through a tolerant lookup that falls back to an `unknown` member, so a server that adds a case does not crash an installed build. Request enums are closed — the server's `z.enum` rejects anything else.
- Catch `FirebaseFunctionsException` once, in the repository, and rethrow a sealed `ApiFailure`. `e.code` is a lowercase hyphenated string (`'permission-denied'`), `e.message` is English developer text for logs only, and `e.details` is the server's `details` object as `dynamic`.
- Unlike the iOS SDK, the Flutter plugin folds transport failures into Functions codes: a socket error becomes `unavailable` and a timeout or cancellation becomes `deadline-exceeded`. Do not write a Dart branch that waits for a separate network error domain.
- Retry only `unavailable`, `deadline-exceeded`, `internal`, and `aborted`, with backoff and a cap. Never retry `invalid-argument`, `permission-denied`, `not-found`, `already-exists`, `failed-precondition`, `resource-exhausted`, or `unauthenticated`. Non-idempotent callables must carry a client-generated id before they may be retried at all.
- Never surface `e.message` or `e.toString()` in the UI. Copy is keyed on the failure type plus `details.reason` and localised in the app.
- `snapshots()` is the app's realtime channel, not a callable in a `Timer`. Type it with `withConverter<T>(fromFirestore:, toFirestore:)` so the stream is `Stream<QuerySnapshot<T>>`, and expose it as a `StreamProvider`.
- Every listener created outside a Riverpod provider needs its `StreamSubscription` cancelled in `dispose`. Inside a provider, return the stream and let Riverpod own the lifecycle; `ref.onDispose` is only for subscriptions you started yourself.
- Keep `cloud_functions` and `cloud_firestore` imports out of `lib/**/presentation/**` entirely. A widget that imports `FirebaseFunctions` is the finding, regardless of what it does with it.
- The background FCM handler must be a top-level, non-anonymous function annotated `@pragma('vm:entry-point')` that calls `await Firebase.initializeApp()` itself — it runs in a separate isolate with no access to your providers.

## Canonical example

The server half is `createNote` in `firebase-skill` → `firebase-functions-pro`. The Dart mirror is three files.

`lib/features/notes/data/note_models.dart`:

```dart
/// Mirrors the server's CreateNoteInput / CreateNoteOutput zod shapes.
enum NoteVisibility {
  private,
  shared,
  unknown;

  static NoteVisibility fromJson(Object? raw) =>
      NoteVisibility.values.firstWhere(
        (v) => v.name == raw,
        orElse: () => NoteVisibility.unknown,
      );

  String toJson() => name;
}

final class CreateNoteRequest {
  const CreateNoteRequest({
    required this.title,
    this.body = '',
    this.visibility = NoteVisibility.private,
    this.tags = const <String>[],
  });

  final String title;
  final String body;
  final NoteVisibility visibility;
  final List<String> tags;

  Map<String, Object?> toJson() => {
        'title': title,
        'body': body,
        'visibility': visibility.toJson(),
        'tags': tags,
      };
}

final class CreateNoteResponse {
  const CreateNoteResponse({
    required this.id,
    required this.title,
    required this.visibility,
    required this.createdAt,
    required this.tags,
  });

  factory CreateNoteResponse.fromJson(Map<String, dynamic> json) =>
      CreateNoteResponse(
        id: json['id'] as String,
        title: json['title'] as String,
        visibility: NoteVisibility.fromJson(json['visibility']),
        createdAt: DateTime.parse(json['createdAt'] as String),
        tags: (json['tags'] as List).cast<String>(),
      );

  final String id;
  final String title;
  final NoteVisibility visibility;
  final DateTime createdAt;
  final List<String> tags;
}
```

`lib/features/notes/data/notes_repository.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../core/api_failure.dart';
import 'note_models.dart';

abstract interface class NotesRepository {
  Future<CreateNoteResponse> createNote(CreateNoteRequest request);
  Stream<List<NoteSummary>> watchNotes({int limit = 50});
}

final class FirebaseNotesRepository implements NotesRepository {
  FirebaseNotesRepository({
    required FirebaseFunctions functions,
    required FirebaseFirestore firestore,
    required this.uid,
  })  : _createNote = functions.httpsCallable(
          'createNote',
          options: const HttpsCallableOptions(timeout: Duration(seconds: 20)),
        ),
        _firestore = firestore;

  final HttpsCallable _createNote;
  final FirebaseFirestore _firestore;
  final String uid;

  @override
  Future<CreateNoteResponse> createNote(CreateNoteRequest request) async {
    try {
      final result = await _createNote.call<Map<String, dynamic>>(request.toJson());
      return CreateNoteResponse.fromJson(result.data);
    } on FirebaseFunctionsException catch (e, s) {
      Error.throwWithStackTrace(ApiFailure.fromFunctions(e), s);
    } on TypeError catch (e, s) {
      Error.throwWithStackTrace(DecodingFailure(debugMessage: '$e'), s);
    }
  }

  @override
  Stream<List<NoteSummary>> watchNotes({int limit = 50}) => _firestore
      .collection('users/$uid/notes')
      .withConverter<NoteSummary>(
        fromFirestore: (snapshot, _) => NoteSummary.fromFirestore(snapshot),
        toFirestore: (value, _) => value.toFirestore(),
      )
      .orderBy('updatedAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((query) => [for (final doc in query.docs) doc.data()]);
}
```

`lib/features/notes/application/notes_providers.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/note_models.dart';
import '../data/notes_repository.dart';

final notesRepositoryProvider = Provider<NotesRepository>(
  (ref) => throw UnimplementedError('Override in main() or in tests'),
);

final notesStreamProvider = StreamProvider<List<NoteSummary>>(
  (ref) => ref.watch(notesRepositoryProvider).watchNotes(),
);

final class CreateNoteController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> submit(CreateNoteRequest request) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(notesRepositoryProvider).createNote(request),
    );
  }
}

final createNoteControllerProvider =
    AsyncNotifierProvider<CreateNoteController, void>(CreateNoteController.new);
```

Provider lifecycle, overrides, and notifier testing are `riverpod-pro`'s territory; the schema, `HttpsError` choice, and security rules are `firebase-skill` → `firebase-functions-pro` and `firebase-security-pro`.

## Output format

If the user asks for a review, organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated.
3. Show a brief before/after code fix.

Skip files with no issues. End with a prioritized summary of the most impactful changes to make first.

If the user asks you to write or improve code, follow the same rules but make the changes directly instead of returning a findings report.

Example output:

### lib/features/notes/data/notes_repository.dart

**Line 34: `call<CreateNoteResponse>()` — the type argument is an unchecked cast over the platform-channel value, so this throws `TypeError` on every call.**

```dart
// Before
final result = await _createNote.call<CreateNoteResponse>(request.toJson());
return result.data;

// After
final result = await _createNote.call<Map<String, dynamic>>(request.toJson());
return CreateNoteResponse.fromJson(result.data);
```

**Line 51: raw `FirebaseFunctionsException` escapes the repository — the widget layer ends up switching on `e.code` strings.**

```dart
// Before
final result = await _createNote.call<Map<String, dynamic>>(request.toJson());

// After
try {
  final result = await _createNote.call<Map<String, dynamic>>(request.toJson());
  return CreateNoteResponse.fromJson(result.data);
} on FirebaseFunctionsException catch (e, s) {
  Error.throwWithStackTrace(ApiFailure.fromFunctions(e), s);
}
```

### lib/features/notes/presentation/note_page.dart

**Line 18: `error.message` shown in a `SnackBar` — untranslated English developer text from the server.**

```dart
// Before
SnackBar(content: Text(error.message ?? 'Error'))

// After
SnackBar(content: Text(context.l10n.messageFor(failure)))
```

### Summary

1. **Contract break (high):** `call<CreateNoteResponse>()` on line 34 fails at runtime for every user.
2. **Error handling (high):** Firebase exception types leak into the UI from line 51 onward.

End of example.

## References

- `references/setup.md` — `flutterfire configure` flags, generated `firebase_options.dart`, `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`, initialisation order in `main()`, flavours and multiple projects, plugin version matrix, iOS deployment target, Android minSdk, per-flavour `GoogleService-Info.plist`.
- `references/callables.md` — `FirebaseFunctions.instanceFor(region:)`, `httpsCallable`, `HttpsCallableOptions` (`timeout`, `limitedUseAppCheckToken`), typed request/response wrappers, `HttpsCallableResult.data` unchecked cast, `int`/`double`/`List` decoding traps, streaming with `stream<T, R>`, `StreamResponse`/`Chunk`/`Result`.
- `references/models-and-serialization.md` — mirroring a zod schema in Dart, hand-written `fromJson` vs `json_serializable` vs `freezed`, ISO-8601 dates with `DateTime.parse`/`toIso8601String`, tolerant enums, nullability contracts, no `Timestamp` through a callable, shared-types discipline.
- `references/error-mapping.md` — `FirebaseFunctionsException` (`code`, `message`, `details`), the full `HttpsError` → Dart code → sealed `ApiFailure` table, decoding `details`, retry policy per code, `unauthenticated` vs `permission-denied` UX, never surfacing raw provider messages.
- `references/firestore-streams.md` — `snapshots()` as the realtime channel, `withConverter`, query construction and runtime index errors, pagination with `startAfterDocument`, `metadata.hasPendingWrites`/`isFromCache`, offline persistence, listener lifecycle and cost, the status-document pattern for long jobs.
- `references/riverpod-integration.md` — repository interface over `FirebaseFunctions`/`FirebaseFirestore`, exposing it as a provider, `StreamProvider` over `snapshots()`, `AsyncValue.guard` around callables, overriding with a fake in tests, keeping Firebase types out of widgets.
- `references/auth-and-appcheck.md` — `authStateChanges` vs `idTokenChanges` vs `userChanges`, `getIdTokenResult(true)` after a custom-claim change, anonymous accounts and `linkWithCredential`, `FirebaseAppCheck.activate` with `providerApple`/`providerAndroid`, debug providers, limited-use tokens, what enforcement breaks locally.
- `references/messaging.md` — `requestPermission`, `getToken`/`onTokenRefresh` and registering the token with the server, `onBackgroundMessage` handler requirements, `onMessage`/`onMessageOpenedApp`/`getInitialMessage`, data-only messages, deep links, iOS APNs prerequisites.
- `references/emulators-and-testing.md` — `useFunctionsEmulator`/`useFirestoreEmulator`/`useAuthEmulator`, `automaticHostMapping` and host choice per platform, `demoProjectId`, seeding, faking the repository in widget tests, what not to test against real Firebase.

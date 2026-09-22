# Riverpod integration

How the Firebase contract is wired into the app without letting `cloud_functions` and `cloud_firestore` escape the data layer. Provider semantics, `Ref` lifecycle, codegen and notifier testing are `riverpod-pro`'s subject; this file covers only the Firebase-shaped decisions.

## The layering rule

```
presentation/   widgets, ConsumerWidget      — sees AsyncValue<Domain> and ApiFailure
application/    providers, notifiers         — sees the repository interface
data/           repository implementation    — the only layer that imports cloud_functions / cloud_firestore
```

A widget that imports `package:cloud_functions/cloud_functions.dart` is a finding regardless of what it does with it. Enforce it mechanically:

```yaml
# analysis_options.yaml
analyzer:
  errors:
    depend_on_referenced_packages: error
```

and, where the team is willing, a `dart_code_metrics`-style banned-import rule on `lib/**/presentation/**`. A grep in review works too; the point is that it is checked, not remembered.

## The repository interface

The interface speaks in domain types and throws `ApiFailure`. It mentions no Firebase type, not even in a generic argument.

```dart
abstract interface class NotesRepository {
  Future<CreateNoteResponse> createNote(CreateNoteRequest request);
  Future<void> deleteNote(String noteId);
  Stream<List<NoteSummary>> watchNotes({int limit = 50});
}
```

```dart
final class FirebaseNotesRepository implements NotesRepository {
  FirebaseNotesRepository({
    required FirebaseFunctions functions,
    required FirebaseFirestore firestore,
    required this.uid,
  })  : _createNote = functions.httpsCallable(
          Fn.createNote,
          options: const HttpsCallableOptions(timeout: Duration(seconds: 20)),
        ),
        _firestore = firestore;
  // ...
}
```

Constructor-inject `FirebaseFunctions` and `FirebaseFirestore` rather than reaching for `.instance` inside methods. That is what makes the emulator wiring, the region and the test doubles a single decision at composition time.

## Providers

```dart
/// Overridden in main() — throws if the root ProviderScope forgot it.
final firebaseFunctionsProvider = Provider<FirebaseFunctions>(
  (ref) => throw UnimplementedError('firebaseFunctionsProvider not overridden'),
);

final firebaseFirestoreProvider = Provider<FirebaseFirestore>(
  (ref) => throw UnimplementedError('firebaseFirestoreProvider not overridden'),
);

final notesRepositoryProvider = Provider<NotesRepository>((ref) {
  final uid = ref.watch(currentUidProvider);
  return FirebaseNotesRepository(
    functions: ref.watch(firebaseFunctionsProvider),
    firestore: ref.watch(firebaseFirestoreProvider),
    uid: uid,
  );
});
```

```dart
runApp(
  ProviderScope(
    overrides: [
      firebaseFunctionsProvider.overrideWithValue(
        FirebaseFunctions.instanceFor(region: 'asia-southeast1'),
      ),
      firebaseFirestoreProvider.overrideWithValue(FirebaseFirestore.instance),
    ],
    child: const MyApp(),
  ),
);
```

- The throwing body plus a root override is the pattern: `main()` is the only place that names a concrete Firebase instance, and a forgotten override fails loudly at first use instead of silently hitting production.
- `notesRepositoryProvider` watches `currentUidProvider`, so signing out rebuilds the repository and disposes every listener scoped to the old user. That is what stops the burst of `permission-denied` errors at sign-out.
- Never construct a repository inside a widget or a notifier field. Providers are the composition root.

## Streams

```dart
final notesStreamProvider = StreamProvider<List<NoteSummary>>(
  (ref) => ref.watch(notesRepositoryProvider).watchNotes(),
);
```

`StreamProvider` owns the subscription: it subscribes on first listen and cancels on dispose. That is the whole reason to prefer it over a `StreamBuilder` whose `stream:` expression is rebuilt on every frame — see `firestore-streams.md`.

In the widget, switch on the sealed `AsyncValue`:

```dart
final notes = ref.watch(notesStreamProvider);

return switch (notes) {
  AsyncData(:final value) when value.isEmpty => const NotesEmptyState(),
  AsyncData(:final value) => NotesList(notes: value),
  AsyncError(:final error) => ErrorView(message: messageFor(asFailure(error), l10n)),
  AsyncLoading() => const CircularProgressIndicator(),
};
```

A Firestore stream error — an index error, a rules denial — arrives as `AsyncError`, not as a thrown exception. Map it with the same `messageFor` used for callables so the two error surfaces do not diverge.

## Callables from a notifier

```dart
final class CreateNoteController extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> submit(CreateNoteRequest request) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => ref.read(notesRepositoryProvider).createNote(request),
    );
    if (!ref.mounted) return;
    state = result;
  }
}
```

- `AsyncValue.guard` captures both the error and its stack trace. A hand-written `try/catch` that assigns `AsyncValue.error(e)` without a stack trace loses the only thing that makes the crash report useful.
- `ref.read` inside a method, never `ref.watch` — a callback that watches re-creates the subscription.
- `if (!ref.mounted) return;` after the await. The screen can be popped mid-call, and Riverpod 3 throws on a disposed `Ref` rather than no-oping.
- The error inside the resulting `AsyncError` is an `ApiFailure`, because the repository converted it. Widgets switch on that, never on `FirebaseFunctionsException`.
- Riverpod 3 retries a failing provider automatically (up to 10 attempts, 200 ms doubling to 6.4 s). For a submission that must fail fast, pass `retry: (count, error) => null` on the provider, or keep the callable in a notifier method where the automatic retry does not apply to a manual `AsyncValue.guard`.

Surfacing the outcome belongs in `ref.listen`, not in `build`:

```dart
ref.listen(createNoteControllerProvider, (previous, next) {
  switch (next) {
    case AsyncError(:final error) when error is UnauthenticatedFailure:
      ref.read(routerProvider).goToSignIn();
    case AsyncError(:final error):
      showSnackBar(messageFor(asFailure(error), l10n));
    case AsyncData() when previous is AsyncLoading:
      Navigator.of(context).pop();
    default:
  }
});
```

## Faking the repository in tests

The interface is the seam. No Firebase, no emulator, no network:

```dart
final class FakeNotesRepository implements NotesRepository {
  FakeNotesRepository({this.onCreate, List<NoteSummary> initial = const []})
      : _controller = StreamController<List<NoteSummary>>.broadcast()
          ..add(initial);

  final Future<CreateNoteResponse> Function(CreateNoteRequest)? onCreate;
  final StreamController<List<NoteSummary>> _controller;

  @override
  Future<CreateNoteResponse> createNote(CreateNoteRequest request) =>
      onCreate?.call(request) ??
      Future.value(CreateNoteResponse(
        id: 'n1',
        title: request.title,
        visibility: request.visibility,
        createdAt: DateTime.utc(2026, 1, 1),
        tags: request.tags,
      ));

  @override
  Future<void> deleteNote(String noteId) async {}

  @override
  Stream<List<NoteSummary>> watchNotes({int limit = 50}) => _controller.stream;

  void emit(List<NoteSummary> notes) => _controller.add(notes);
}
```

```dart
testWidgets('shows the sign-in prompt when the callable is unauthenticated', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notesRepositoryProvider.overrideWithValue(
          FakeNotesRepository(
            onCreate: (_) async => throw const UnauthenticatedFailure(),
          ),
        ),
      ],
      child: const MyApp(),
    ),
  );

  await tester.tap(find.byKey(const Key('save')));
  await tester.pumpAndSettle();

  expect(find.text('Please sign in to continue.'), findsOneWidget);
});
```

- Override `notesRepositoryProvider`, not `firebaseFunctionsProvider`. Mocking `FirebaseFunctions` means mocking `HttpsCallable` and `HttpsCallableResult` and reproducing the plugin's decoding — all of which is the thing you are trying not to depend on.
- The fake throws `ApiFailure` subtypes directly. Every row of the mapping table in `error-mapping.md` becomes a one-line widget test.
- `StreamController.broadcast()` plus an `emit` method covers "a new document arrives while the screen is open", which is the behaviour worth testing about a listener.
- Test-level provider mechanics — `ProviderContainer.test()`, `overrideWithBuild`, `WidgetTester.container` — are `riverpod-pro` → `references/testing.md`. Widget and golden test structure is `flutter-testing-pro`. What runs against the emulator suite instead is `emulators-and-testing.md`.

## Does not exist / common mistakes

- `FirebaseFirestore.instance` called directly inside a provider body — untestable and unhookable to the emulator; inject it.
- A `StreamProvider` whose body creates the query inline from `FirebaseFirestore.instance` — the same problem, plus the query is rebuilt on every provider rebuild.
- `ref.watch` inside `onPressed` or a notifier method — use `ref.read`.
- Assigning `state = AsyncValue.error(e)` by hand — drop the stack trace and the crash report is useless. Use `AsyncValue.guard`.
- `state = ...` after an await without `if (!ref.mounted) return;` — throws in Riverpod 3.
- A repository method that returns `Future<HttpsCallableResult<Map<String, dynamic>>>` — the Firebase type has escaped the layer.
- Mocking `FirebaseFunctions` with `mockito` — fake the repository interface instead.
- `showDialog` or navigation from inside a provider or a `build` method — belongs in `ref.listen`; see `riverpod-pro`.
- Keeping the repository alive across sign-out — it holds the old `uid` and its listeners fail rules. Derive it from the auth provider so it rebuilds.

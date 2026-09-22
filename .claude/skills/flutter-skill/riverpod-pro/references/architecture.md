# Architecture, dependency injection, and lints

Riverpod is the app's DI container as well as its state layer. That makes the shape of the
provider graph an architectural decision, not a styling one. Load this file when reviewing folder
layout, where business logic lives, how external dependencies are injected, or the analyser
configuration.

## Feature-first layout

```
lib/
  main.dart                       // the only place that names concrete implementations
  core/
    providers/
      clients.dart                // http.Client, Dio, FirebaseFirestore injection points
      clock.dart
    errors/
      app_exception.dart
  features/
    todos/
      data/
        todo_repository.dart      // interface + implementation + injection provider
        todo_dto.dart
      application/
        todo_list.dart            // AsyncNotifier + derived providers
        todo_filters.dart
      presentation/
        todo_list_page.dart       // ConsumerWidget
        widgets/
    auth/
      data/ application/ presentation/
```

Three layers, and the dependency arrows point one way only:

| Layer | Contains | May import |
|---|---|---|
| `data` | repositories, DTOs, mapping to/from the wire | `core`, packages |
| `application` | providers, notifiers, derived state | `data`, `core` |
| `presentation` | `ConsumerWidget`s | `application`, `core`, Flutter |

`data` never imports `presentation`. `application` never imports `package:material_ui/material_ui.dart`.
A provider that needs `BuildContext` is a design error — `riverpod_lint`'s
`avoid_build_context_in_providers` enforces it.

## The repository boundary

Providers must not call HTTP, Firestore, or `SharedPreferences` directly. Put an interface
between them:

```dart
abstract interface class TodoRepository {
  Future<List<Todo>> fetchAll();
  Future<void> setDone(String id, {required bool done});
}

class FirestoreTodoRepository implements TodoRepository {
  FirestoreTodoRepository(this._db, this._uid);
  final FirebaseFirestore _db;
  final String _uid;
  // ...
}
```

This is what makes `testing.md`'s fakes possible and keeps Firestore types out of the notifier.
The Firestore/callable/FCM specifics on the Flutter side are `flutter-firebase-contract`'s.

## Dependency injection by override

The pattern: a provider whose body throws, overridden once at the root.

```dart
// core/providers/clients.dart
@Riverpod(keepAlive: true)
FirebaseFirestore firestore(Ref ref) =>
    throw UnimplementedError('Override firestoreProvider in main()');

@Riverpod(keepAlive: true)
Clock clock(Ref ref) => const SystemClock();   // a real default is fine when it is pure
```

```dart
// main.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(
    ProviderScope(
      overrides: [firestoreProvider.overrideWithValue(FirebaseFirestore.instance)],
      child: const MyApp(),
    ),
  );
}
```

Why the throwing body rather than a default:

- A test that forgets to fake the dependency fails loudly instead of hitting the network.
- `main()` is the only file that knows about `FirebaseFirestore.instance`, so flavours, emulators
  and integration tests differ by one list of overrides.
- Async initialisation (opening a database, reading a token) happens once in `main`, not on the
  first widget build.

Use a real default only for pure, side-effect-free dependencies (a clock, a UUID generator, a
formatter) where the real implementation is safe in a test.

Everything built **on top of** an injection point is an ordinary provider and needs no override:

```dart
@riverpod
TodoRepository todoRepository(Ref ref) =>
    FirestoreTodoRepository(ref.watch(firestoreProvider), ref.watch(uidProvider));
```

Note `watch`, not `read`: swapping the override or signing a different user in rebuilds the
repository and everything above it.

## Navigation and platform code

Neither belongs in a provider.

- **Navigation** is a widget concern. React to state with `ref.listen` in the widget and call
  `Navigator`/`GoRouter` there. If the router itself must be reactive, expose the *state* it needs
  from a provider (`isSignedIn`, `pendingDeepLink`) and let the router watch it — the router
  object may live in a `Provider`, but it must never be pushed to from a notifier.
- **Platform channels, permissions, notifications, file pickers** go behind a service interface in
  `data`, injected the same way as a repository. The notifier calls `ref.read(serviceProvider)`
  and never touches `MethodChannel` directly.
- **`BuildContext`** never crosses into `application`. Passing `context` into a notifier method is
  the same bug as storing it in a field.

## Scoping

Scoping is a second `ProviderScope` (or `ProviderContainer`) mid-tree that overrides a provider
for a subtree. It is the right tool for "this page has a current item and everything below should
see it", and the wrong tool for almost everything else.

```dart
// The scoped provider opts in with an empty dependencies list.
final currentItemIdProvider = Provider<String>(
  dependencies: const [],
  (ref) => throw UnimplementedError('scoped per route'),
);

// Anything reading it must declare it.
final currentItemProvider = FutureProvider<Item>(
  dependencies: [currentItemIdProvider],
  (ref) => ref.watch(repoProvider).fetch(ref.watch(currentItemIdProvider)),
);

// The route supplies the value.
ProviderScope(
  overrides: [currentItemIdProvider.overrideWithValue(id)],
  child: const ItemDetailPage(),
);
```

With codegen the declaration is the annotation's `dependencies` list, holding the *annotated
function or class names*, not the generated provider names:

```dart
@Riverpod(dependencies: [])                       // opts in to being scoped
String currentItemId(Ref ref) => throw UnimplementedError('scoped per route');

@Riverpod(dependencies: [currentItemId])
Future<Item> currentItem(Ref ref) =>
    ref.watch(repoProvider).fetch(ref.watch(currentItemIdProvider));
```

Reading a scoped provider from a container that never overrode it throws
`MissingScopeException`.

`riverpod_lint` makes this statically checkable in 3.x: `provider_dependencies` reports a provider
that reads a scoped provider without declaring it, and `scoped_providers_should_specify_dependencies`
reports overriding a provider that never opted in. A missing declaration used to be a runtime
surprise; now it is an analyser error. The Riverpod docs themselves note that scoping is complex
and may be reworked — prefer a family argument over a scope wherever both would work.

## Lint setup

```yaml
# analysis_options.yaml
include: package:flutter_lints/flutter.yaml

plugins:
  riverpod_lint: ^3.1.9

analyzer:
  errors:
    missing_provider_scope: error
    provider_dependencies: error
    notifier_extends: error
    avoid_build_context_in_providers: error
    provider_parameters: error
```

Riverpod 3's lints run as a native analyser plugin. Do **not** add `custom_lint` as a dev
dependency or an `analyzer: plugins: - custom_lint` block — that was the Riverpod 2 setup and it
no longer applies.

Rules worth promoting to `error`:

| Rule | Catches |
|---|---|
| `missing_provider_scope` | no `ProviderScope` above `runApp` |
| `provider_dependencies` | a scoped provider read without being declared |
| `scoped_providers_should_specify_dependencies` | overriding a provider that did not opt into scoping |
| `avoid_build_context_in_providers` | `BuildContext` leaking into the application layer |
| `provider_parameters` | family arguments without stable `==`/`hashCode` |
| `avoid_public_notifier_properties` | state hidden in public fields where Riverpod cannot see it |
| `avoid_keep_alive_dependency_inside_auto_dispose` | a `keepAlive` provider watching an auto-dispose one |
| `notifier_extends` / `notifier_build` | `@riverpod` classes not extending `_$X` or missing `build` |
| `functional_ref` | a generated provider function without a plain `Ref` first parameter |
| `avoid_ref_inside_state_dispose` | `ref` used in `State.dispose` |
| `async_value_nullable_pattern` | `AsyncValue(:final value?)` matching over a nullable `T` |
| `unsupported_provider_value` | a `StateNotifier`/`ChangeNotifier` handed to a modern provider |
| `protected_notifier_properties` | one notifier reaching into another's `state` |
| `riverpod_syntax_error` | a malformed annotation the generator rejected |

The IDE assists that ship with the plugin — wrap in `Consumer`, wrap in `ProviderScope`, convert
to `ConsumerWidget`/`ConsumerStatefulWidget`, convert functional `@riverpod` to class form and
back — are the fastest way to apply half the fixes in this skill.

## Provider observers

`ProviderObserver` is the single place for logging state transitions, reporting provider errors to
Crashlytics, and timing rebuilds. In Riverpod 3 its callbacks take a `ProviderObserverContext`
carrying the container, the provider and any active mutation, instead of the Riverpod 2 parameter
list. Register with `ProviderScope(observers: [...])`. Log the provider `name`, so set `name:` on
anything you expect to appear in a crash report.

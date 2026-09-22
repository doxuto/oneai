# Code generation with `@riverpod`

`riverpod_generator` removes the "which provider class do I need?" question: you write a function
or a class, and the generator picks `Provider`, `FutureProvider`, `StreamProvider`,
`NotifierProvider`, `AsyncNotifierProvider` or `StreamNotifierProvider` from the return type.
Load this file when reviewing anything annotated `@riverpod`, when a `.g.dart` file is out of
sync, or when deciding whether a project should adopt codegen at all.

## Setup

```yaml
# pubspec.yaml
environment:
  sdk: ^3.13.0
  flutter: ">=3.47.0"

dependencies:
  flutter:
    sdk: flutter
  flutter_riverpod: ^3.4.3
  riverpod_annotation: ^4.0.7

dev_dependencies:
  build_runner:
  riverpod_generator: ^4.0.9
```

```yaml
# analysis_options.yaml
plugins:
  riverpod_lint: ^3.1.9
```

Riverpod 3's lints load through the analyser's native `plugins:` key. The Riverpod 2 recipe —
a `custom_lint` dev dependency plus an `analyzer: plugins: - custom_lint` block — is obsolete.

Generate with `dart run build_runner watch -d` during development, `dart run build_runner build
--delete-conflicting-outputs` in CI. Every annotated file needs:

```dart
part 'the_same_file_name.g.dart';
```

Missing or misspelled `part` directives are the most frequent build_runner failure. The generated
file is committed or gitignored consistently across the repo — pick one and do not mix.

## Function-style providers

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'api.g.dart';

@riverpod
String label(Ref ref) => 'Hello world';           // -> Provider<String>, labelProvider

@riverpod
Future<User> user(Ref ref) async =>               // -> FutureProvider<User>, userProvider
    ref.watch(apiProvider).fetchUser();

@riverpod
Stream<int> ticks(Ref ref) async* {               // -> StreamProvider<int>, ticksProvider
  yield* someStream;
}
```

The first parameter is always `Ref` — plain, unparameterised. Riverpod 2 generated a per-provider
ref type (`LabelRef`, `UserRef`); those no longer exist and `riverpod_lint`'s `functional_ref`
rule flags the old signature.

## Class-style providers

Use a class the moment the UI needs to call a method.

```dart
@riverpod
class Counter extends _$Counter {
  @override
  int build() => 0;                 // -> NotifierProvider<Counter, int>, counterProvider

  void increment() => state = state + 1;
}

@riverpod
class TodoList extends _$TodoList {
  @override
  Future<List<Todo>> build() =>     // -> AsyncNotifierProvider<TodoList, List<Todo>>
      ref.watch(todoRepositoryProvider).fetchAll();

  Future<void> add(Todo todo) async { /* ... */ }
}
```

The generated base class is `_$ClassName`. `riverpod_lint` enforces this with `notifier_extends`
and `notifier_build`. Never write `extends Notifier<int>` on an `@riverpod` class — the generated
base already does that, and the annotation will not compile against it.

## Naming rules

| You write | Generator emits |
|---|---|
| `String label(Ref ref)` | `labelProvider` |
| `Future<User> fetchUser(Ref ref)` | `fetchUserProvider` |
| `class Counter extends _$Counter` | `counterProvider`, base `_$Counter` |
| `class TodoListNotifier extends _$TodoListNotifier` | `todoListNotifierProvider` (unless stripped) |
| a function or `build` with parameters | a family; call it as `fooProvider(arg)` |

The suffixes are configurable in `build.yaml`:

```yaml
targets:
  $default:
    builders:
      riverpod_generator:
        options:
          provider_name_prefix: ""
          provider_family_name_prefix: ""
          provider_name_suffix: "Provider"
          provider_family_name_suffix: "Provider"
          provider_name_strip_pattern: "Notifier$"
```

`provider_name_strip_pattern` is how teams that name classes `XNotifier` still get `xProvider`.
Leave these at their defaults unless the project already committed to another convention.

## Auto-dispose

`@riverpod` is **auto-dispose**. This is the opposite of a hand-written provider, where
`isAutoDispose` defaults to `false`.

```dart
@riverpod
Future<Feed> feed(Ref ref) => ...;            // disposed when unwatched

@Riverpod(keepAlive: true)
Database database(Ref ref) => ...;            // lives for the container's lifetime
```

The annotation's full signature is
`Riverpod({bool keepAlive = false, List<Object>? dependencies, Duration? Function(int, Object)? retry, String? name})`.
`dependencies` lists the annotated *functions and classes* (not the generated `xProvider` names)
and is only needed for scoping; `name` renames the generated provider; `retry` sets a
per-provider retry policy.

Use `keepAlive: true` for singletons: repositories, clients, database handles, injection points.
Use the default for anything scoped to a screen. Conditional caching still uses `ref.keepAlive()`
inside the body — the annotation and the runtime call compose.

## Families are function parameters

Any parameter after `Ref` (or any parameter on `build`) becomes a family argument. Named,
optional and default parameters all work, which the `.family` modifier cannot express.

```dart
@riverpod
Future<List<Product>> products(
  Ref ref, {
  required int page,
  int limit = 50,
}) async =>
    ref.watch(apiProvider).products(page: page, limit: limit);

// Consumption
final page1 = ref.watch(productsProvider(page: 1));
```

For class-style providers the arguments go on `build`, **not** on the constructor:

```dart
@riverpod
class Session extends _$Session {
  @override
  Future<User> build(String userId) => ref.watch(apiProvider).fetchUser(userId);

  Future<void> rename(String name) async { /* userId is in scope via the build arg */ }
}

ref.watch(sessionProvider('u-42'));
```

This is the exact inverse of the hand-written form, where the argument goes on the notifier's
constructor. Getting it backwards is the most common Riverpod 3 codegen error. To reach the
argument from another method, store it in a field during `build`, or read it from the generated
getter the base class exposes (verify the generated member name in `.g.dart` before using it).

The same equality requirement as manual families applies: arguments must have stable `==` and
`hashCode`, so prefer scalars, enums, records, or classes with value equality.

## Generic providers (new in 3.0)

Codegen providers can carry type parameters:

```dart
@riverpod
T multiply<T extends num>(Ref ref, T a, T b) => (a * b) as T;

final six = ref.watch(multiplyProvider<int>(2, 3));
```

Use it for genuinely reusable machinery (a cache keyed by type, a generic decoder). Do not
reach for it to avoid writing two concrete providers — the generated code grows quickly.

## When not to use codegen

| Situation | Verdict |
|---|---|
| The project already runs `build_runner` for `freezed`/`json_serializable` | Use codegen. The marginal build cost is near zero. |
| A small app with no other generators | Skip it. `NotifierProvider<N, T>(N.new)` is four extra characters. |
| A package meant to be consumed by others | Skip it, or keep the generated file committed so consumers need no generator. |
| You need scoping | Use `@Riverpod(dependencies: [...])` — see `architecture.md`. |
| A quick spike or a test fixture | Skip it; hand-written providers need no build step. |

Mixed projects are fine: `@riverpod` and hand-written providers interoperate freely, watch each
other, and override each other. What must not be mixed is *style within one feature*.

## Reviewing generated code

- A `.g.dart` diff that does not match the source means `build_runner` was not rerun. Flag it.
- `riverpod_syntax_error` from the linter means the generator refused the annotation; read the
  message rather than editing `.g.dart`.
- Never edit a `.g.dart` file. Never import one directly; the `part` directive is the link.
- Generated providers expose the same surface as hand-written ones — `.future`, `.notifier`,
  `.select`, `overrideWith`, `overrideWithValue` — so `testing.md` applies unchanged.

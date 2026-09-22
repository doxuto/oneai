---
name: riverpod-pro
description: Writes, reviews, and refactors Riverpod 3 state management and dependency injection for Flutter apps using flutter_riverpod 3.4.3, riverpod_annotation, and riverpod_generator. Use when reading, writing, or reviewing code that uses ProviderScope, ConsumerWidget, ref.watch, ref.listen, Notifier, AsyncNotifier, AsyncValue, NotifierProvider, FutureProvider, ProviderContainer, overrideWith, or the @riverpod annotation, or when the user mentions Riverpod, providers, auto-dispose, keepAlive, provider scoping, StateNotifier, or migrating Riverpod 2 to 3.
license: MIT
metadata:
  author: doxuto
  version: "1.0"
  targets: "flutter_riverpod 3.4.3, riverpod_annotation 4.0.7, riverpod_generator 4.0.9, riverpod_lint 3.1.9, Flutter 3.47.5, Dart 3.13.4"
---

Write and review Riverpod 3 code for correctness, lifecycle safety, rebuild cost, and testability. The single biggest risk in this area is Riverpod 2 syntax that still compiles in some places and silently misbehaves in others — flag it every time. Report only genuine problems — do not nitpick or invent issues.

## Core principles

1. **Riverpod 3 has six provider types and no `AutoDispose*` classes.** `Provider`, `FutureProvider`, `StreamProvider`, `NotifierProvider`, `AsyncNotifierProvider`, `StreamNotifierProvider`. `AutoDisposeNotifier`, `FamilyNotifier`, `AutoDisposeAsyncNotifierProvider` and friends were deleted in 3.0; there is one `Notifier` and one `AsyncNotifier`. The `.autoDispose` and `.family` *modifiers* still exist.
2. **There is exactly one `Ref`.** No `ProviderRef`, `FutureProviderRef`, `StreamProviderRef`, `AutoDisposeRef`, and no type argument on `Ref`. A provider function signature is `(Ref ref)`. Inside a `Notifier` you use the inherited `ref`.
3. **`state` is replaced, never mutated.** Riverpod 3 filters updates with `==`. `state.add(x)` mutates the same object, `==` is true, and no listener rebuilds. Build a new list/map/object and assign it.
4. **`watch` declares a dependency, `read` takes a snapshot, `listen` runs a side effect.** `ref.watch` belongs in `build` and in provider bodies. `ref.read` belongs in callbacks and notifier methods. Dialogs, snackbars, navigation and analytics belong in `ref.listen`, never in `build`.
5. **Providers own the read; notifiers own the write; repositories own the I/O.** A provider body is a pure description of how to produce state. Never `POST` from a `FutureProvider` body, never touch `BuildContext` from a provider, and never let a provider import `package:material_ui/material_ui.dart` at all.
6. **`AsyncValue` is sealed — switch over it.** `AsyncData`, `AsyncLoading`, `AsyncError` are exhaustive, so `switch` and if-case give compile-time coverage that `when` does not. `valueOrNull` no longer exists; the nullable accessor is `value`.
7. **Every async gap needs a liveness check.** Providers are auto-disposed, paused when their widgets go off-screen, and recreated on rebuild. After an `await` inside a notifier method, check `if (!ref.mounted) return;` before assigning to `state`.

## Review process

1. Check provider choice, modifiers, auto-dispose posture, and `keepAlive` using `references/providers.md`.
2. Check `@riverpod` annotations, generated names, `part` directives, and build_runner setup using `references/codegen.md`.
3. Check `Notifier`/`AsyncNotifier` anatomy, `build()` contracts, state mutation, and side-effect methods using `references/notifiers.md`.
4. Check `watch`/`read`/`listen` placement, subscriptions, lifecycle callbacks, and invalidation using `references/ref-lifecycle.md`.
5. Check `AsyncValue` handling, pattern matching, error surfaces, and retry behaviour using `references/async-state.md`.
6. Check `ConsumerWidget`, `Consumer` scoping, `ProviderScope` placement, and UI side effects using `references/widgets.md`.
7. Check `ProviderContainer.test()`, overrides, and notifier tests using `references/testing.md`.
8. Check folder layout, repository boundaries, dependency injection, and lint configuration using `references/architecture.md`.
9. Flag any Riverpod 2 API, removed class, or hallucinated symbol using `references/migration-and-mistakes.md`.

If doing a partial review, load only the relevant reference files.

## Core instructions

- Import Material from `package:material_ui/material_ui.dart` and Cupertino from `package:cupertino_ui/cupertino_ui.dart`. Flutter 3.47 decoupled both out of the SDK; `package:flutter/material.dart` still compiles but its classes are *distinct types* from the package's, so mixing the two produces "argument type X is not the type X" errors. Migrate with `dart fix --apply --code=migrate_design_widgets`. See `flutter-widgets-pro` → `references/material3-theming.md`.
- Target `flutter_riverpod: ^3.4.3`. With codegen add `riverpod_annotation: ^4.0.7` and dev-dependency `riverpod_generator: ^4.0.9` plus `build_runner`. Lints come from `riverpod_lint: ^3.1.9` declared under the top-level `plugins:` key in `analysis_options.yaml` — Riverpod 3 no longer needs a `custom_lint` dev dependency or the `analyzer: plugins: - custom_lint` block.
- Reject `StateProvider`, `StateNotifierProvider`, `ChangeNotifierProvider` and `StateNotifier` in new code. They still ship, but only from `package:flutter_riverpod/legacy.dart` (or `package:riverpod/legacy.dart`, `package:hooks_riverpod/legacy.dart`). Replace with `NotifierProvider` + `Notifier`.
- A provider is not auto-dispose by default without codegen: the constructor parameter is `isAutoDispose: false`. With codegen it is the reverse — `@riverpod` is auto-dispose and `@Riverpod(keepAlive: true)` opts out. State these explicitly rather than assuming.
- Family arguments go in the *constructor* for hand-written notifiers (`MyNotifier(this.id)` + `AsyncNotifierProvider.family(MyNotifier.new)`), and in the `build()` *parameters* for `@riverpod` classes. Mixing the two is the most common Riverpod 3 family bug.
- Family parameters must have stable `==`/`hashCode`. `ref.watch(p([1, 2, 3]))` creates a new provider instance on every rebuild. Use a scalar, a record, or a class with value equality; `riverpod_lint`'s `provider_parameters` catches this.
- Guard every `state =` that follows an `await` with `if (!ref.mounted) return;`. Touching a disposed `Ref` throws in Riverpod 3 instead of silently no-oping.
- Wrap fallible work in notifier methods with `AsyncValue.guard(() async { ... })` and assign the result. Do not hand-write `try/catch` that sets `AsyncValue.error(e)` without the stack trace.
- Use `switch`/if-case over `AsyncValue` in widgets rather than `when(data:, error:, loading:)`. `when` compiles even when a case is wrong; the sealed hierarchy makes `switch` exhaustive. Keep `when` only where all three branches are genuinely one-liners.
- Never call `ref.read` inside `build` (of a provider or a widget) to obtain state that can change — it captures a stale value and registers no dependency. The only legitimate `read` in a build method is fetching a `.notifier` to hand to a callback, and even that is better done inside the callback.
- Never call `ref.watch` inside a callback, `initState`, `onPressed`, or a `Timer`. Use `ref.read`, or `ref.listen` if you need to react over time.
- Narrow rebuilds with `ref.watch(provider.select((s) => s.field))`, and narrow the subtree with a `Consumer` builder rather than making a whole page a `ConsumerWidget`.
- Use `ref.invalidate(p)` when you do not need the new value and `ref.refresh(p)` when you do. For pull-to-refresh, `onRefresh: () => ref.refresh(p.future)` so the indicator waits for the real completion.
- Inject every external dependency (HTTP client, Firestore, `SharedPreferences`, clock) through a provider whose body throws `UnimplementedError`, overridden once in the root `ProviderScope`. This is what makes tests cheap and keeps `main()` the only place that knows about concrete implementations.
- Providers must be top-level `final` variables. Creating a provider inside `build`, inside a widget field, or inside another provider leaks state on every rebuild.
- Automatic retry is on by default (up to 10 attempts, 200 ms doubling to 6.4 s). For a user-facing action that must fail fast, pass `retry: (count, error) => null` on the provider or on `ProviderScope`; do not let a form submission silently retry for a minute.
- Keep `BuildContext` out of providers entirely — `riverpod_lint`'s `avoid_build_context_in_providers` enforces it. Navigation and platform channels belong in the widget layer; see `flutter-widgets-pro`.
- Mark `Mutation`, `persist()`/`riverpod_sqflite`, and `CustomProviderListenable` as experimental whenever they appear; their APIs may change within the 3.x line.

## Canonical example

`lib/features/todos/data/todo_repository.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'todo_repository.g.dart';

class Todo {
  const Todo({required this.id, required this.title, required this.done});
  final String id;
  final String title;
  final bool done;

  Todo copyWith({String? title, bool? done}) =>
      Todo(id: id, title: title ?? this.title, done: done ?? this.done);
}

abstract interface class TodoRepository {
  Future<List<Todo>> fetchAll();
  Future<void> setDone(String id, {required bool done});
}

/// Injection point: the body always throws. `main()` overrides it, tests
/// override it with a fake, and nothing else in the app names a concrete class.
@Riverpod(keepAlive: true)
TodoRepository todoRepository(Ref ref) =>
    throw UnimplementedError('Override todoRepositoryProvider in ProviderScope');
```

`lib/features/todos/application/todo_list.dart`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../data/todo_repository.dart';

part 'todo_list.g.dart';

@riverpod
class TodoList extends _$TodoList {
  @override
  Future<List<Todo>> build() {
    // watch, not read: swapping the repository override rebuilds this provider.
    return ref.watch(todoRepositoryProvider).fetchAll();
  }

  Future<void> toggle(String id) async {
    final todos = await future; // AsyncNotifier.future — resolves past loading
    final target = todos.firstWhere((t) => t.id == id);
    final repository = ref.read(todoRepositoryProvider);

    // Optimistic update: a brand-new list, because `==` filters identical state.
    state = AsyncValue.data([
      for (final t in todos)
        if (t.id == id) t.copyWith(done: !t.done) else t,
    ]);

    final result = await AsyncValue.guard(
      () => repository.setDone(id, done: !target.done),
    );

    if (!ref.mounted) return; // disposed while the write was in flight
    if (result case AsyncError(:final error, :final stackTrace)) {
      state = AsyncValue.data(todos); // roll back, then let the caller report it
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
```

`lib/features/todos/presentation/todo_list_page.dart`:

```dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/todo_list.dart';
import '../data/todo_repository.dart';

class TodoListPage extends ConsumerWidget {
  const TodoListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Side effects live in listen, never in build.
    ref.listen<AsyncValue<List<Todo>>>(todoListProvider, (previous, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load todos: $error')));
      }
    });

    final todos = ref.watch(todoListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Todos')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(todoListProvider.future),
        child: switch (todos) {
          AsyncValue(:final value?) => ListView.builder(
              itemCount: value.length,
              itemBuilder: (context, i) {
                final todo = value[i];
                return CheckboxListTile(
                  key: ValueKey(todo.id),
                  value: todo.done,
                  title: Text(todo.title),
                  onChanged: (_) async {
                    try {
                      await ref.read(todoListProvider.notifier).toggle(todo.id);
                    } on Object catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not save: $error')),
                      );
                    }
                  },
                );
              },
            ),
          AsyncValue(:final error?) => _ErrorView(
              error: error,
              onRetry: () => ref.invalidate(todoListProvider),
            ),
          _ => const Center(child: CircularProgressIndicator()),
        },
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$error'),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}
```

`lib/main.dart`:

```dart
void main() {
  runApp(
    ProviderScope(
      overrides: [
        todoRepositoryProvider.overrideWithValue(HttpTodoRepository()),
      ],
      child: const MyApp(),
    ),
  );
}
```

Widget-level concerns in the page above — keys, layout, `RefreshIndicator` semantics, Material 3 theming — belong to `flutter-widgets-pro`. The widget and golden tests for it belong to `flutter-testing-pro`.

## Output format

If the user asks for a review, organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated.
3. Show a brief before/after code fix.

Skip files with no issues. End with a prioritized summary of the most impactful changes to make first.

If the user asks you to write or improve code, follow the same rules but make the changes directly instead of returning a findings report.

Example output:

### lib/features/todos/application/todo_list.dart

**Line 24: `state` mutated in place — `==` is true against the previous list, so no listener rebuilds.**

```dart
// Before
state.value!.add(newTodo);

// After
final todos = state.requireValue;
state = AsyncValue.data([...todos, newTodo]);
```

**Line 31: `state` assigned after an `await` with no liveness check — throws if the provider was disposed mid-flight.**

```dart
// Before
await repository.save(todo);
state = AsyncValue.data(updated);

// After
await repository.save(todo);
if (!ref.mounted) return;
state = AsyncValue.data(updated);
```

### lib/features/todos/presentation/todo_list_page.dart

**Line 12: `AutoDisposeAsyncNotifierProvider` referenced in a type annotation — the class does not exist in Riverpod 3.**

```dart
// Before
final AutoDisposeAsyncNotifierProvider<TodoList, List<Todo>> p = todoListProvider;

// After
final AsyncNotifierProvider<TodoList, List<Todo>> p = todoListProvider;
```

### Summary

1. **Correctness (high):** In-place mutation on line 24 means the toggle never reaches the UI.
2. **Crash (high):** Unguarded post-`await` assignment on line 31 throws once the page is popped during a slow write.
3. **Compile (high):** Removed Riverpod 2 type on line 12.

End of example.

## References

- `references/providers.md` — the six Riverpod 3 provider types and when to pick each, `Provider`/`FutureProvider`/`StreamProvider`/`NotifierProvider`/`AsyncNotifierProvider`/`StreamNotifierProvider`, `.family` and `.autoDispose` modifiers, `isAutoDispose`, disposal timing, `ref.keepAlive` and `KeepAliveLink`, `.future`/`.notifier`/`.stream` accessors, decision table.
- `references/codegen.md` — `@riverpod` and `@Riverpod(keepAlive: true)`, `riverpod_annotation` + `riverpod_generator` + `build_runner` setup, `part 'x.g.dart'`, generated provider names and `_$Class` bases, function-style vs class-style, family arguments as parameters, generic providers, `build.yaml` naming options, when not to use codegen.
- `references/notifiers.md` — `Notifier` and `AsyncNotifier` anatomy, the `build()` contract, `state` / `stateOrNull` / `requireValue`, replacing rather than mutating state, family args via constructor, `future`, `update`, `updateShouldNotify`, `listenSelf`, side-effect methods, `AsyncValue.guard`, `ref.mounted` after async gaps.
- `references/ref-lifecycle.md` — the unified `Ref`, `watch` vs `read` vs `listen` decision table, `ProviderSubscription` with `pause`/`resume`/`close`, `onDispose`/`onCancel`/`onResume`/`onAddListener`/`onRemoveListener` and their `RemoveListener` returns, weak listeners, `invalidate`/`invalidateSelf`/`refresh`, `keepAlive`, `select`, automatic pausing of off-screen widgets, `isPaused`/`isReload`/`isRefresh`.
- `references/async-state.md` — sealed `AsyncValue`, `AsyncData`/`AsyncLoading`/`AsyncError`, pattern matching vs `when`/`maybeWhen`, `value` (was `valueOrNull`), `requireValue`, `isLoading`/`hasValue`/`isRefreshing`/`isReloading`/`isFromCache`/`retrying`, `AsyncLoading.progress`, preserving data across refresh, automatic retry and the `retry:` parameter, `ProviderException`, error surfaces in the UI.
- `references/widgets.md` — `ConsumerWidget`, `ConsumerStatefulWidget`/`ConsumerState`, `Consumer` for scoped rebuilds, `WidgetRef` vs `Ref`, `ProviderScope` at the root, `hooks_riverpod` and `HookConsumerWidget`, showing dialogs and snackbars from `ref.listen`, `listenManual`, pull-to-refresh with `ref.refresh(p.future)`.
- `references/testing.md` — `ProviderContainer.test()`, `container.read`/`listen`/`pump`, `WidgetTester.container`, `overrideWith` vs `overrideWithValue` vs `overrideWithBuild`, overriding families, awaiting `.future`, faking repositories, testing notifiers without a widget tree, `ProviderObserver` in tests.
- `references/architecture.md` — feature-first folder layout, repository and service layers under providers, dependency injection by overriding an `UnimplementedError` provider, keeping `BuildContext` out of providers, where navigation and platform code belong, scoping with `dependencies` and `@Riverpod(dependencies: [...])`, `MissingScopeException`, `riverpod_lint` setup and the rules worth enforcing.
- `references/migration-and-mistakes.md` — Riverpod 2 to 3 migration table, `legacy.dart` imports, removed `AutoDispose*` and typed `Ref` classes, `valueOrNull`, `ref.read` in `build`, `watch` in callbacks, providers created inside `build`, `StateNotifier`, and the correct 3.x replacement for each.

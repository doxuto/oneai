# Provider types in Riverpod 3

Riverpod 3 collapsed a sprawl of provider classes into six. Every `AutoDispose*` class, every
`Family*Notifier`, and every typed `Ref` was deleted. Load this file when choosing a provider,
when reviewing a provider declaration, or when a type name in the code does not appear in the
grid below.

## The grid

Rows are "can the UI change this?", columns are the Dart return type of the body.

| | Synchronous | `Future` | `Stream` |
|---|---|---|---|
| **Read-only** | `Provider<T>` | `FutureProvider<T>` | `StreamProvider<T>` |
| **Mutable** | `NotifierProvider<N, T>` | `AsyncNotifierProvider<N, T>` | `StreamNotifierProvider<N, T>` |

That is the complete list. `StateProvider`, `StateNotifierProvider` and `ChangeNotifierProvider`
still exist but only under `package:flutter_riverpod/legacy.dart`; see `migration-and-mistakes.md`.

## Decision table

| Situation | Provider | Why |
|---|---|---|
| A service object, repository, or `http.Client` | `Provider` | Never changes; also the injection point for overrides. |
| A value derived from other providers (filtering, mapping, totals) | `Provider` | Recomputes only when a watched dependency changes. |
| One-shot fetch the UI only reads | `FutureProvider` | Gives you `AsyncValue` and `.future` for free. |
| Firestore/WebSocket subscription the UI only reads | `StreamProvider` | Cancels the subscription on dispose. |
| Synchronous state with commands (counter, filter, form model) | `NotifierProvider` | Public methods are the only write path. |
| Async-initialised state with commands (a list loaded then edited) | `AsyncNotifierProvider` | `build()` returns `Future<T>`; methods mutate afterwards. |
| Stream-initialised state with commands | `StreamNotifierProvider` | `build()` returns `Stream<T>`. |

Rule of thumb: if the UI only reads, use the read-only row. The moment you need a method the UI
can call, move to the matching notifier. Do not expose a `Provider<SomeController>` where the
controller holds mutable fields — that bypasses Riverpod's update filtering entirely.

## Declaration, without codegen

```dart
final clockProvider = Provider<Clock>((ref) => const Clock());

final userProvider = FutureProvider<User>((ref) async {
  return ref.watch(apiProvider).fetchUser();
});

final ticksProvider = StreamProvider<int>((ref) {
  final controller = StreamController<int>();
  ref.onDispose(controller.close);
  return controller.stream;
});

final counterProvider = NotifierProvider<Counter, int>(Counter.new);

class Counter extends Notifier<int> {
  @override
  int build() => 0;

  void increment() => state = state + 1;
}
```

The constructors share a shape:

```dart
Provider(
  Create<ValueT> create, {
  String? name,
  Iterable<ProviderOrFamily>? dependencies,
  bool isAutoDispose = false,
  Retry? retry,
})
```

`FutureProvider`, `StreamProvider` and `NotifierProvider` take the same named parameters;
`NotifierProvider`'s positional argument is a `NotifierT Function()` (normally `MyNotifier.new`).

| Parameter | Purpose |
|---|---|
| `name` | Label shown in the devtool and in `ProviderObserver` output. Cheap; set it on anything you will debug. |
| `dependencies` | Declares which *scoped* providers this one reads. Only needed for scoping — see `architecture.md`. |
| `isAutoDispose` | `false` by default without codegen. Set `true` for anything per-screen. |
| `retry` | `Duration? Function(int retryCount, Object error)`. Returning `null` stops retrying. |

## Modifiers

`.autoDispose` and `.family` are still present in Riverpod 3 and are still chained before the
type arguments.

```dart
final searchProvider = FutureProvider.autoDispose.family<List<Hit>, String>(
  (ref, query) async => ref.watch(apiProvider).search(query),
);

final hit = ref.watch(searchProvider('flutter'));
```

`.autoDispose` and `isAutoDispose: true` are the same switch expressed two ways; pick one style
per codebase. What was removed is the *type* `AutoDisposeFutureProvider`, not the modifier.

For notifier families the argument arrives through the notifier's **constructor**:

```dart
final userProvider =
    AsyncNotifierProvider.autoDispose.family<UserNotifier, User, String>(UserNotifier.new);

class UserNotifier extends AsyncNotifier<User> {
  UserNotifier(this.id);
  final String id;

  @override
  Future<User> build() => ref.watch(apiProvider).fetchUser(id);
}
```

In Riverpod 2 the argument was a `build(String id)` parameter. That form is gone for hand-written
notifiers. With codegen it is the opposite — see `codegen.md`.

### Family argument equality

A family keys its cache on the argument's `==`/`hashCode`. Passing a fresh `List` or a closure
creates a new provider instance on every rebuild and leaks state.

```dart
// Wrong — a new list every build
ref.watch(itemsProvider([1, 2, 3]));

// Right — a record, or any type with value equality
ref.watch(itemsProvider((page: 1, limit: 20)));
```

`riverpod_lint`'s `provider_parameters` rule catches the common cases.

## Automatic disposal

A provider is disposed when it has had no listeners for a full frame. The sequence is:

1. Last listener removed → `ref.onCancel` fires.
2. One frame passes.
3. Still unlistened → `ref.onDispose` fires and state is destroyed.

If a listener reattaches in step 2, `ref.onResume` fires instead and nothing is destroyed.

### `ref.keepAlive()` and `KeepAliveLink`

```dart
final configProvider = FutureProvider.autoDispose<Config>((ref) async {
  final config = await ref.watch(apiProvider).fetchConfig();
  ref.keepAlive(); // only cache a *successful* result
  return config;
});
```

`keepAlive()` returns a `KeepAliveLink`; calling `link.close()` re-arms automatic disposal. The
canonical time-boxed cache is an extension:

```dart
extension CacheFor on Ref {
  void cacheFor(Duration duration) {
    final link = keepAlive();
    final timer = Timer(duration, link.close);
    onDispose(timer.cancel);
  }
}

final feedProvider = FutureProvider.autoDispose<Feed>((ref) async {
  ref.cacheFor(const Duration(minutes: 5));
  return ref.watch(apiProvider).fetchFeed();
});
```

### Pausing

New in 3.0: a provider whose listeners are all invisible (their widgets are under a disabled
`TickerMode`, e.g. an inactive tab or a route underneath another) is **paused**, not disposed.
Paused providers stop rebuilding and propagate the pause to what they watch. `ref.isPaused`
reports it. A `StreamProvider` under a paused consumer keeps its subscription but stops
delivering rebuilds — if you need the stream to keep firing, add a non-widget listener with
`ref.listen` from a keep-alive provider.

## Accessors on a provider

| Accessor | Available on | Yields |
|---|---|---|
| `p` | all | the state (`T`, or `AsyncValue<T>` for async providers) |
| `p.future` | `FutureProvider`, `AsyncNotifierProvider`, `StreamNotifierProvider` | `Future<T>` that resolves past loading and retries |
| `p.notifier` | the three notifier providers | the notifier instance, for calling methods |
| `p.select((v) => x)` | all | a narrowed listenable; rebuilds only when `x` changes |
| `p.selectAsync((v) => x)` | async providers | `ProviderListenable<Future<OutT>>` — the async counterpart of `select` |

`p.notifier` and `p.future` are `Refreshable`s, which is why `ref.refresh(p.future)` is legal and
why `ref.read(p.notifier)` does not subscribe you to state changes.

`StreamProvider` has **no** `.stream` accessor in Riverpod 3. Watch the `AsyncValue`, or await
`.future` for the first emitted value. Code calling `ref.watch(p.stream)` is Riverpod 2.

## Anti-patterns

```dart
// Wrong: a provider created inside build — new instance and new state every rebuild.
Widget build(BuildContext context, WidgetRef ref) {
  final p = Provider((ref) => 0);
  return Text('${ref.watch(p)}');
}

// Wrong: a provider as an instance field.
class Repo { final cacheProvider = Provider((ref) => Cache()); }

// Right: top-level final, always.
final cacheProvider = Provider((ref) => Cache());
```

```dart
// Wrong: a write in a read-only provider body. Reruns on any invalidation.
final submitProvider = FutureProvider((ref) async {
  return ref.watch(apiProvider).post(ref.watch(formProvider));
});

// Right: a method on a notifier, called from a callback.
ref.read(formProvider.notifier).submit();
```

Combining providers is `ref.watch`, never constructor injection:

```dart
final visibleTodosProvider = Provider<List<Todo>>((ref) {
  final todos = ref.watch(todoListProvider).value ?? const [];
  return todos.where(ref.watch(filterProvider).matches).toList();
});
```

That derived provider recomputes only when a watched dependency changes, and its own listeners
only rebuild when the result differs by `==` — so the value type needs real value equality. See
`dart-pro` for `==`/`hashCode` and sealed data classes.

# `Notifier` and `AsyncNotifier`

Notifiers are where Riverpod keeps mutable state. Riverpod 3 has exactly three notifier base
classes — `Notifier<T>`, `AsyncNotifier<T>`, `StreamNotifier<T>` — all descending from
`AnyNotifier`. `AutoDisposeNotifier`, `FamilyNotifier`, `AutoDisposeFamilyAsyncNotifier` and the
rest were deleted in 3.0. Load this file when reviewing any class that extends one of them.

## Anatomy

```dart
final counterProvider = NotifierProvider<Counter, int>(Counter.new);

class Counter extends Notifier<int> {
  @override
  int build() => 0;                       // must return synchronously

  void increment() => state = state + 1;  // side-effect method
}
```

```dart
final todosProvider = AsyncNotifierProvider<TodoList, List<Todo>>(TodoList.new);

class TodoList extends AsyncNotifier<List<Todo>> {
  @override
  Future<List<Todo>> build() =>           // FutureOr<List<Todo>>
      ref.watch(todoRepositoryProvider).fetchAll();

  Future<void> add(String title) async { /* ... */ }
}
```

Note the state types: `Counter.state` is `int`, but `TodoList.state` is `AsyncValue<List<Todo>>`.
`AsyncNotifier<T>` exposes `AsyncValue<T>` while `build()` returns `FutureOr<T>`.

## Members

| Member | On | Notes |
|---|---|---|
| `build()` | all | Called on first read and on every rebuild. Must be `@override`. |
| `state` | all | Getter and setter. `T` for `Notifier`, `AsyncValue<T>` for `AsyncNotifier`. |
| `stateOrNull` | all | `T?` — safe to read before `build` has completed. |
| `ref` | all | The unified `Ref`. Not a constructor parameter; it is inherited. |
| `future` | `AsyncNotifier`, `StreamNotifier` | `Future<T>` resolving to the next non-loading value. |
| `update(cb)` | `AsyncNotifier` | `Future<T>`; applies `cb` to the current value, awaiting loading and rethrowing errors. |
| `listenSelf(listener, {onError})` | all | Returns a `RemoveListener`. Replaces Riverpod 2's `Ref.listenSelf`. |
| `updateShouldNotify(prev, next)` | all | Defaults to `prev != next`. Override to widen or narrow notifications. |

## The `build()` contract

1. **`build()` must be pure with respect to the outside world.** No HTTP POST, no analytics
   event, no navigation, no `showDialog`. It describes how to produce the initial state.
2. **`build()` runs again whenever a watched dependency changes, or after `invalidate`/`refresh`.**
   Everything a rebuild should re-derive belongs in `build()`; everything that must survive a
   rebuild does not belong in a notifier field.
3. **Do not assign to `state` inside `build()`.** Return the value. Assigning inside `build`
   double-notifies and breaks the initial-value contract.
4. **`build()` is where you register lifecycle callbacks** — `ref.onDispose`, `ref.listen`,
   `ref.keepAlive` — because they must be re-registered on every rebuild.

```dart
class Search extends AsyncNotifier<List<Hit>> {
  @override
  Future<List<Hit>> build() async {
    final client = http.Client();
    ref.onDispose(client.close);          // re-registered each rebuild; correct

    await Future<void>.delayed(const Duration(milliseconds: 300)); // debounce
    if (!ref.mounted) throw const _Cancelled();  // disposed during the debounce

    return ref.watch(apiProvider).search(ref.watch(queryProvider), client: client);
  }
}
```

Errors thrown after disposal are swallowed by Riverpod, which is what makes the debounce pattern
safe.

## `state` is replaced, never mutated

Riverpod 3 filters updates with `==` for every provider (Riverpod 2 used `identical` in places).
Mutating the object already in `state` therefore produces no rebuild at all.

```dart
// Wrong — same List instance, == is true, nothing rebuilds
state.requireValue.add(todo);

// Wrong — same object, == is true if Todo has value equality
state.requireValue.first.done = true;

// Right — a new list
state = AsyncValue.data([...state.requireValue, todo]);

// Right — a new element inside a new list
state = AsyncValue.data([
  for (final t in state.requireValue)
    if (t.id == id) t.copyWith(done: true) else t,
]);
```

The corollary: state types need real value equality, or `==` will be identity and every
assignment notifies. Use `freezed`, a hand-written `==`/`hashCode`, or a record. See `dart-pro`.

`riverpod_lint`'s `avoid_public_notifier_properties` exists for the same reason — public fields on
a notifier are state that Riverpod cannot observe.

## Family arguments

For **hand-written** notifiers the argument arrives through the constructor:

```dart
final userProvider =
    AsyncNotifierProvider.autoDispose.family<UserNotifier, User, String>(UserNotifier.new);

class UserNotifier extends AsyncNotifier<User> {
  UserNotifier(this.id);
  final String id;

  @override
  Future<User> build() => ref.watch(apiProvider).fetchUser(id);

  Future<void> rename(String name) async {
    await ref.read(apiProvider).rename(id, name);   // `id` available everywhere
    if (!ref.mounted) return;
    ref.invalidateSelf();
  }
}
```

Riverpod 2's `Future<User> build(String id)` on a `FamilyAsyncNotifier` no longer compiles.
For **codegen** notifiers it is the reverse: the argument stays on `build()` and the generator
writes the constructor. See `codegen.md`.

## Side-effect methods

A notifier method is the only sanctioned write path. The shape is: read what you need, perform
the effect, then decide what `state` becomes.

```dart
Future<void> add(String title) async {
  final repository = ref.read(todoRepositoryProvider);

  state = const AsyncValue.loading();
  state = await AsyncValue.guard(() async {
    await repository.create(title);
    return repository.fetchAll();
  });
}
```

`AsyncValue.guard` runs the callback, returns `AsyncData` on success and `AsyncError` with the
real stack trace on failure. Hand-rolled `try/catch` that builds `AsyncValue.error(e,
StackTrace.current)` loses the original trace — flag it.

For a snappier UI, update optimistically and roll back:

```dart
Future<void> toggle(String id) async {
  final todos = await future;                 // waits out loading and retries
  state = AsyncValue.data([
    for (final t in todos) if (t.id == id) t.copyWith(done: !t.done) else t,
  ]);

  final result = await AsyncValue.guard(() => ref.read(repoProvider).toggle(id));
  if (!ref.mounted) return;
  if (result case AsyncError()) state = AsyncValue.data(todos);
}
```

### `update`

`AsyncNotifier.update` packages "take the current value, transform it, write it back" and handles
the loading/error cases for you:

```dart
Future<void> markAllDone() =>
    update((todos) => [for (final t in todos) t.copyWith(done: true)]);
```

Prefer it over `state = AsyncValue.data(f(state.requireValue))`, which throws if the notifier is
mid-load.

## `ref.mounted` after async gaps

Riverpod 3 throws when you touch a disposed `Ref` or a disposed notifier, rather than silently
ignoring the call. Every `await` inside a notifier method is a chance for the provider to be
disposed (the route was popped, an auto-dispose timer fired, a dependency invalidated).

```dart
// Wrong
Future<void> save() async {
  await repository.save(draft);
  state = AsyncValue.data(draft);     // may throw
}

// Right
Future<void> save() async {
  await repository.save(draft);
  if (!ref.mounted) return;
  state = AsyncValue.data(draft);
}
```

Check `ref.mounted` after *every* await that precedes a `state` assignment, a `ref.read`, or a
`ref.invalidate`. This mirrors `BuildContext.mounted` in the widget layer.

## `updateShouldNotify` and `listenSelf`

```dart
class Position extends Notifier<LatLng> {
  @override
  LatLng build() => const LatLng(0, 0);

  // Ignore sub-metre jitter.
  @override
  bool updateShouldNotify(LatLng previous, LatLng next) =>
      previous.distanceTo(next) > 1.0;
}
```

`listenSelf` reacts to your own state changes from inside the notifier — persisting a draft,
logging transitions — and returns a `RemoveListener` you can call to detach early.

```dart
@override
Draft build() {
  listenSelf((previous, next) => ref.read(draftStoreProvider).save(next));
  return ref.read(draftStoreProvider).load();
}
```

Do not use `listenSelf` to derive a second piece of state; derive it in a separate `Provider`
that watches this one.

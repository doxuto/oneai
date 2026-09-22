# Riverpod 2 → 3, and the APIs that get hallucinated

Riverpod 3.0 removed more API than any previous release, and most of what it removed still
appears in tutorials, Stack Overflow answers and model output. Load this file whenever you see a
symbol that is not in `providers.md`'s grid, whenever a codebase is being upgraded, and as the
last pass of any review.

## Migration table

| Riverpod 2 | Riverpod 3 | Note |
|---|---|---|
| `AutoDisposeProvider<T>` | `Provider<T>` | The `.autoDispose` modifier and `isAutoDispose:` remain; the *type* is gone. |
| `AutoDisposeNotifier<T>` | `Notifier<T>` | Same for `AutoDisposeAsyncNotifier`, `AutoDisposeStreamNotifier`. |
| `FamilyNotifier<T, A>` | `Notifier<T>` | Family argument moves to the notifier's constructor. |
| `FamilyAsyncNotifier<T, A>` | `AsyncNotifier<T>` | Same. |
| `AutoDisposeFamilyAsyncNotifier<T, A>` | `AsyncNotifier<T>` | Both prefixes gone at once. |
| `Future<T> build(A arg)` on a family notifier | `MyNotifier(this.arg)` + `Future<T> build()` | Hand-written notifiers only; codegen keeps args on `build`. |
| `ProviderRef<T>`, `FutureProviderRef<T>`, `StreamProviderRef<T>`, `NotifierProviderRef<T>`, `AutoDisposeRef` | `Ref` | One class, no type parameter. |
| `ExampleRef` (generated) | `Ref` | `riverpod_lint`'s `functional_ref` flags the old signature. |
| `ProviderRef.state` | `Notifier.state` | A read-only provider has no settable state; use a notifier. |
| `Ref.listenSelf` | `Notifier.listenSelf` | Moved off `Ref`. |
| `FutureProviderRef.future` | `AsyncNotifier.future` | |
| `AsyncValue.valueOrNull` | `AsyncValue.value` | Same semantics: the previous value if there is one, else `null`. |
| `StateProvider` | `NotifierProvider` + `Notifier` | Still available from `legacy.dart`. |
| `StateNotifierProvider` / `StateNotifier` | `NotifierProvider` + `Notifier` | Still available from `legacy.dart`. |
| `ChangeNotifierProvider` | `NotifierProvider` with an immutable state | Still available from `legacy.dart`. |
| `ProviderObserver(provider, container, ...)` | `ProviderObserver(ProviderObserverContext context, ...)` | Parameters consolidated. |
| hand-rolled `createContainer()` test helper | `ProviderContainer.test()` | Disposal is automatic. |
| `ProviderScope.containerOf(tester.element(...))` | `tester.container()` | From `RiverpodWidgetTesterX`. |
| `custom_lint` dev dependency + `analyzer: plugins:` | top-level `plugins: riverpod_lint:` in `analysis_options.yaml` | Native analyser plugin. |
| `family.overrideWith(...)` | `family.overrideWith2(...)` | Deprecated in 3.2.0; check the pinned version. |
| `StreamProvider.stream` | watch the `AsyncValue`, or `await p.future` | The `.stream` accessor is gone. |
| update filtering by `identical` | update filtering by `==` | Mutating state in place now never notifies. |

## Behavioural changes with no API surface

These break code that still compiles.

1. **Equality filtering everywhere.** Every provider compares old and new state with `==`.
   `state.add(x)` followed by no reassignment produces no rebuild. Replace the object.
2. **Automatic retry is on.** A failing provider retries up to 10 times, 200 ms doubling to
   6.4 s. Tests that await a failing `.future` hang for ~38 s; non-idempotent work retries
   silently. Pass `retry: (count, error) => null` where that is wrong.
3. **Off-screen providers pause.** Listeners under a disabled `TickerMode` stop receiving
   notifications and the pause propagates upstream. Work that must continue off-screen needs a
   non-widget listener.
4. **A disposed `Ref` throws.** Riverpod 2 tolerated post-dispose interaction; 3.x raises. Every
   `state =` or `ref.read` after an `await` needs `if (!ref.mounted) return;`.
5. **Errors are wrapped.** `ref.watch`/`ref.read` rethrowing a dependency's failure wraps it in
   `ProviderException`; unwrap with `.exception` before type-checking.
6. **Providers are recreated on rebuild.** This is what makes `Ref.mounted` meaningful; notifier
   instance fields do not survive a rebuild, so derive everything in `build()`.
7. **`AsyncValue.value` keeps the previous value through an error or a refresh**, and is `null`
   only when no value was ever produced. Audit `.value!` on error paths accordingly.

## Mechanical upgrade order

1. Bump `flutter_riverpod` to `^3.4.3` (and `riverpod_annotation` `^4.0.7` /
   `riverpod_generator` `^4.0.9` if using codegen). Rerun `build_runner`.
2. Replace the `custom_lint` setup with `plugins: riverpod_lint:`; fix what the analyser reports.
3. Delete every `AutoDispose` and `Family` prefix from type names; add `.autoDispose` or
   `isAutoDispose: true` where the removed prefix implied it.
4. Replace every typed `Ref` with `Ref`.
5. Move family notifier arguments from `build(...)` to the constructor (hand-written only).
6. Rename `valueOrNull` to `value`; audit every `.value!` for the error case.
7. Add `if (!ref.mounted) return;` after every `await` that precedes a `state =`.
8. Decide the retry policy — global default, or per-provider opt-out.
9. Migrate `StateProvider`/`StateNotifierProvider` to `Notifier`, or add the `legacy.dart`
   import as a deliberate, time-boxed stopgap.
10. Replace test helpers with `ProviderContainer.test()` and `tester.container()`.

## Legacy imports

If a migration cannot finish in one pass:

```dart
import 'package:flutter_riverpod/legacy.dart';   // Flutter
import 'package:hooks_riverpod/legacy.dart';     // Flutter + hooks
import 'package:riverpod/legacy.dart';           // Dart-only
```

That library exports `StateProvider`, `StateProviderFamily`, `StateNotifier`,
`StateNotifierProvider`, `StateNotifierProviderFamily`, `StateController`,
`ChangeNotifierProvider`, `ChangeNotifierProviderFamily`. Nothing else moved there. New code
importing `legacy.dart` is a finding.

## Wrong-but-circulating patterns

Each of these compiles somewhere or reads plausibly, and each is wrong in 3.x.

```dart
// Wrong: type removed in 3.0.
final p = AutoDisposeFutureProvider<int>((ref) async => 1);
// Right:
final p = FutureProvider<int>(isAutoDispose: true, (ref) async => 1);
```

```dart
// Wrong: typed refs are gone.
final p = FutureProvider<int>((FutureProviderRef<int> ref) async => 1);
// Right:
final p = FutureProvider<int>((Ref ref) async => 1);
```

```dart
// Wrong: removed accessor.
final user = ref.watch(userProvider).valueOrNull;
// Right:
final user = ref.watch(userProvider).value;
```

```dart
// Wrong: ref.read in build — stale, and no dependency registered.
Widget build(BuildContext context, WidgetRef ref) => Text('${ref.read(countProvider)}');
// Right:
Widget build(BuildContext context, WidgetRef ref) => Text('${ref.watch(countProvider)}');
```

```dart
// Wrong: watch inside a callback.
onPressed: () => ref.watch(cartProvider.notifier).add(item),
// Right:
onPressed: () => ref.read(cartProvider.notifier).add(item),
```

```dart
// Wrong: a provider created during build — fresh state every frame, leaked every frame.
Widget build(BuildContext context, WidgetRef ref) {
  final local = StateProvider((ref) => 0);
  return Text('${ref.watch(local)}');
}
// Right: a top-level provider, or plain widget state for something this local.
```

```dart
// Wrong: mutating state.
state.todos.add(todo);
state.count++;
// Right:
state = state.copyWith(todos: [...state.todos, todo]);
```

```dart
// Wrong: StateNotifier in new code.
class Counter extends StateNotifier<int> {
  Counter() : super(0);
  void increment() => state++;
}
// Right:
class Counter extends Notifier<int> {
  @override
  int build() => 0;
  void increment() => state = state + 1;
}
```

```dart
// Wrong: side effect in a read-only provider body; reruns on every invalidation.
final loginProvider = FutureProvider((ref) => api.login(ref.watch(formProvider)));
// Right: a method on a notifier, invoked from a callback.
ref.read(loginProvider.notifier).submit();
```

```dart
// Wrong: `ref` captured after disposal.
Future<void> save() async {
  await repo.save(draft);
  state = AsyncValue.data(draft);   // throws if disposed mid-write
}
// Right:
Future<void> save() async {
  await repo.save(draft);
  if (!ref.mounted) return;
  state = AsyncValue.data(draft);
}
```

```dart
// Wrong: refresh that does not await the data — the indicator disappears instantly.
RefreshIndicator(onRefresh: () async => ref.refresh(pProvider), child: ...)
// Right:
RefreshIndicator(onRefresh: () => ref.refresh(pProvider.future), child: ...)
```

```dart
// Wrong: dialog during build.
if (state.hasError) showDialog(context: context, builder: ...);
// Right: register the reaction once, at the top of build.
ref.listen(pProvider, (previous, next) { if (next.hasError) showDialog(...); });
```

## Symbols that do not exist

Reject these on sight; none of them are Riverpod 3 API.

`ref.watchAsync`, `ref.readAsync`, `ref.state`, `ref.mounted()` (it is a getter, not a call),
`Ref<T>` with a type argument, `AsyncNotifierProviderRef`, `NotifierProvider.autoDisposeFamily`
as a single identifier, `AsyncValue.data()` without an argument, `AsyncValue.guard` used
synchronously, `ProviderScope.of(context)` (it is `ProviderScope.containerOf(context, {listen = true})`),
`StreamProvider.stream` (removed in 3.x — watch the `AsyncValue` or await `.future`),
`context.watch`/`context.read` (that is `package:provider`), `ConsumerStatelessWidget`,
`StateNotifierProvider.autoDispose` outside `legacy.dart`, `riverpod_annotation`'s `@Riverpod()`
with a `dependencies` argument written as strings rather than provider identifiers.

If you are unsure whether a symbol survived, check
`https://pub.dev/documentation/flutter_riverpod/latest/` before writing it. Do not guess a
plausible name.

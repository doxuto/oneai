# `Ref`, listening, and lifecycle

Riverpod 3 has a single `Ref` class with no type parameter. Every `Ref` subclass from Riverpod 2
— `ProviderRef`, `FutureProviderRef`, `StreamProviderRef`, `NotifierProviderRef`, all the
`AutoDispose*Ref` variants — was deleted. Load this file when reviewing where `watch`/`read`/
`listen` are called, when a provider disposes or rebuilds unexpectedly, or when subscriptions are
being managed by hand.

## `watch` vs `read` vs `listen`

| | `ref.watch` | `ref.read` | `ref.listen` |
|---|---|---|---|
| Creates a dependency | yes | no | yes (a subscription) |
| Rebuilds on change | yes | no | no — runs a callback |
| Legal in a provider body / `build()` | **yes, default** | only for one-shot values | yes, register once per build |
| Legal in a widget `build` | **yes, default** | only to fetch `.notifier` | yes |
| Legal in a callback (`onPressed`, `initState`) | **no** | **yes, default** | no (use `listenManual`) |
| Legal in `dispose` | no | no (`avoid_ref_inside_state_dispose`) | no |
| Returns | the value | the value | `ProviderSubscription` (`Ref`) / `void` (`WidgetRef`) |

Decision procedure:

1. Does the code need to re-run when the value changes? If no → `ref.read`.
2. Is the re-run "rebuild this widget/provider"? If yes → `ref.watch`.
3. Is the re-run "do something once" — a snackbar, a navigation, a log, a controller update?
   → `ref.listen`.

```dart
// Wrong: read in build captures a stale value and registers no dependency.
Widget build(BuildContext context, WidgetRef ref) {
  final count = ref.read(counterProvider);
  return Text('$count');
}

// Wrong: watch in a callback. Throws, or subscribes at a moment that cannot unsubscribe.
onPressed: () => ref.watch(counterProvider.notifier).increment(),

// Right
Widget build(BuildContext context, WidgetRef ref) {
  final count = ref.watch(counterProvider);
  return TextButton(
    onPressed: () => ref.read(counterProvider.notifier).increment(),
    child: Text('$count'),
  );
}
```

## `Ref` surface

| Member | Signature | Notes |
|---|---|---|
| `watch` | `StateT watch<StateT>(ProviderListenable<StateT>)` | Takes a listenable, so `p.select(...)` works. |
| `read` | `StateT read<StateT>(ProviderListenable<StateT>)` | |
| `listen` | `ProviderSubscription<StateT> listen<StateT>(ProviderListenable<StateT>, void Function(StateT? previous, StateT next), {void Function(Object, StackTrace)? onError, bool weak = false, bool fireImmediately = false})` | `previous` is nullable on the first call. |
| `exists` | `bool exists(ProviderBase<Object?>)` | True if the provider is already initialised. |
| `invalidate` | `void invalidate(ProviderOrFamily, {bool asReload = false})` | Accepts a whole family. |
| `invalidateSelf` | `void invalidateSelf({bool asReload = false})` | |
| `refresh` | `StateT refresh<StateT>(Refreshable<StateT>)` | Invalidate + read, synchronously. |
| `keepAlive` | `KeepAliveLink keepAlive()` | See `providers.md`. |
| `onDispose` / `onCancel` / `onResume` / `onAddListener` / `onRemoveListener` | `RemoveListener onX(void Function())` | Each returns a function that unregisters it. |
| `notifyListeners` | `void notifyListeners()` | Forces a notification without changing `state`. Last resort. |
| `mounted` | `bool` | False once disposed. |
| `container` | `ProviderContainer` | |
| `isFirstBuild` / `isReload` / `isRefresh` / `isPaused` | `bool` | Distinguish first build from a dependency-driven reload from an explicit `refresh`. |

`WidgetRef` is a different type and deliberately shares no base class with `Ref`. It has
`context`, `container`, `watch`, `read`, `listen` (returning `void`), `listenManual` (returning a
subscription), `refresh`, `invalidate`, `exists`. Code that needs both is code that should be
moved into a notifier.

## `ref.listen` and subscriptions

```dart
@override
Future<Session> build() async {
  final sub = ref.listen(authProvider, (previous, next) {
    if (next is SignedOut) ref.invalidateSelf();
  }, onError: (error, stack) => log('auth failed', error: error));

  ref.onDispose(sub.close);   // optional inside a provider; automatic on dispose
  return ...;
}
```

`ProviderSubscription` exposes `read()`, `close()`, `pause()`, `resume()`, and the flags `closed`,
`isPaused`, `weak`. Subscriptions created inside a provider are closed automatically when the
provider is disposed; `listenManual` subscriptions created from a `ConsumerState` are not, and
must be closed in `dispose`.

`pause()`/`resume()` are new in 3.0. Use them to stop an expensive listener while a screen is
backgrounded without tearing down the provider:

```dart
class _State extends ConsumerState<Map> with WidgetsBindingObserver {
  late final ProviderSubscription<Position> _sub;

  @override
  void initState() {
    super.initState();
    _sub = ref.listenManual(positionProvider, _onMove);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) =>
      s == AppLifecycleState.resumed ? _sub.resume() : _sub.pause();

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}
```

### Weak listeners

`weak: true` listens without keeping the provider alive. The callback fires only while the
provider exists for some other reason; it will never cause initialisation and never prevents
auto-disposal.

```dart
ref.listen(analyticsSourceProvider, weak: true, (previous, next) => log(next));
```

Use it for observers — logging, metrics — that must not change lifetime semantics.

## Lifecycle callbacks

| Callback | Fires when | Typical use |
|---|---|---|
| `onAddListener` | a listener is attached | instrumentation |
| `onRemoveListener` | a listener detaches | instrumentation |
| `onCancel` | the **last** listener detaches | start a disposal timer, pause a socket |
| `onResume` | a listener reattaches after `onCancel` | resume the socket |
| `onDispose` | the state is destroyed | close controllers, clients, timers, subscriptions |

All five return a `RemoveListener` — a zero-argument function that unregisters the callback:

```dart
final removeDisposeHook = ref.onDispose(temporaryCleanup);
// ... later, when cleanup is no longer needed
removeDisposeHook();
```

Register them inside the provider body or `build()`, never conditionally after an `await` — a
rebuild re-runs the body and re-registers them from scratch.

`ref.onDispose` is the cancellation hook for I/O:

```dart
final searchProvider = FutureProvider.autoDispose.family<List<Hit>, String>((ref, q) async {
  final client = http.Client();
  ref.onDispose(client.close);      // in-flight request aborts when the user navigates away
  return (await client.get(Uri.parse('/search?q=$q'))).decode();
});
```

## Invalidation

| Call | Effect |
|---|---|
| `ref.invalidate(p)` | Marks `p` stale. Rebuilds at the next frame if listened, destroys it if not. |
| `ref.invalidate(family)` | Invalidates every instantiated member of the family. |
| `ref.invalidate(p, asReload: true)` | Same, but the resulting `AsyncValue` reports `isReloading` rather than `isRefreshing`. |
| `ref.invalidateSelf()` | The provider re-runs its own body. |
| `ref.refresh(p)` | `invalidate` + `read`, synchronously, returning the new value. |
| `ref.refresh(p.future)` | Returns the `Future<T>`, so `await` completes when the data lands. |

Use `invalidate` when the new value is not needed at the call site, `refresh` when it is. Calling
`refresh` and discarding the result is a smell — it forces an immediate rebuild for nothing.

## Narrowing with `select`

```dart
// Rebuilds on any change to the user object
final name = ref.watch(userProvider).name;

// Rebuilds only when the name changes
final name = ref.watch(userProvider.select((u) => u.name));
```

`select` compares with `==`, so the selected value must have value equality; selecting a freshly
built list or map defeats it. For async providers, `selectAsync` gives the same narrowing over
the resolved value and yields a `Future`:

```dart
final title = await ref.watch(articleProvider.selectAsync((a) => a.title));
```

`select` works anywhere a `ProviderListenable` is accepted — `watch`, `read`, `listen`,
`container.listen`.

## Automatic pausing

A provider whose listeners are all invisible is paused: its widgets are under a disabled
`TickerMode` (an inactive `TabBarView` page, a route covered by another route). Paused providers
stop rebuilding, and the pause propagates to everything they watch. `ref.isPaused` reports it.

Consequences worth flagging in review:

- A provider that must keep working off-screen (a location tracker, an upload queue) needs a
  listener that is not a widget — hold it from a `keepAlive` provider with `ref.listen`.
- Timers and stream subscriptions inside a provider keep running while paused; only the
  notification of listeners stops. Do not rely on pausing to throttle I/O.
- `TickerMode(enabled: true)` around a subtree opts that subtree back in.

During a provider rebuild, its previous subscriptions are paused rather than dropped, so a
watched auto-dispose provider is not destroyed across an async gap in `build()`. This fixed a
long-standing Riverpod 2 footgun where `await` inside a provider body could dispose its own
dependencies.

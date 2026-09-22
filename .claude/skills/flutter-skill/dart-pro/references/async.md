# Asynchrony

Dart is single-threaded per isolate with two queues: microtasks and events. Almost every async bug in a Flutter app is one of four things — a future nobody awaited, a subscription nobody cancelled, a controller nobody closed, or work that should have been on another isolate. This file covers the APIs and the hygiene rules.

## The two queues

| Queue | Fed by | Drained |
|---|---|---|
| Microtask | `scheduleMicrotask`, `Future.microtask`, the continuation of an `await`, `Future.value(...).then` | completely, before any event |
| Event | `Timer`, `Future.delayed`, I/O, stream events, platform messages, frames | one at a time; microtasks drain after each |

Consequences:

- A `while` loop that keeps adding microtasks starves the event queue: no frames, no I/O, a frozen UI.
- `await null;` yields to the microtask queue only. To let a frame render you need an event-queue turn: `await Future<void>.delayed(Duration.zero)`.
- `Future.value(x)` is *not* synchronous: `.then` still runs in a microtask.

## `Future` essentials

| API | Behaviour |
|---|---|
| `Future(() => ...)` | runs the computation in a later **event**-queue turn (`Timer.run`) |
| `Future.microtask(() => ...)` | runs it in the microtask queue |
| `Future.sync(() => ...)` | runs it **now**, synchronously; errors become a failed future rather than a throw |
| `Future.value(v)` / `Future.error(e, st)` | already-completed future |
| `Future.delayed(d, [computation])` | event queue after `d`; cannot be cancelled |
| `Future.wait(futures, {eagerError = false, cleanUp})` | `Future<List<T>>`; see below |
| `Future.any(futures)` | first to complete, value or error |
| `Future.forEach` / `Future.doWhile` | sequential iteration |
| `f.timeout(d, onTimeout:)` | throws `TimeoutException` if `f` is slow; **does not cancel `f`** |
| `f.then(onValue, onError:)` | `onError` catches errors from `f` only, not from `onValue` |
| `f.catchError(handler, test:)` | `test` selects which errors to handle |
| `f.whenComplete(action)` | runs on both paths; the `finally` of futures |
| `f.ignore()` | discards the result **and** silences the error |

### `Future.wait` error behaviour

- Default (`eagerError: false`): waits for **every** future, then completes with the first error reported, in list order of reporting. Errors from the others are silently dropped unless `cleanUp` is supplied.
- `eagerError: true`: completes with the first error as soon as it happens. The other futures keep running to completion; their results and errors are discarded.
- `cleanUp: (value) { ... }` runs for each successfully produced value when the whole call ends in error — the only hook for releasing resources the losing futures produced.
- Nothing is cancelled, ever. Dart futures have no cancellation. If you need it, pass a flag or a `CancellationToken`-style object you check yourself, or use a `StreamSubscription`.

```dart
// Before — one failure hides the others and leaks the opened files
final handles = await Future.wait(paths.map(open));

// After
final handles = await Future.wait(
  paths.map(open),
  eagerError: true,
  cleanUp: (h) => h.close(),
);
```

### `unawaited`

```dart
import 'dart:async';

unawaited(analytics.log('note_opened')); // deliberate; errors go to the zone
```

`void unawaited(Future<void>? future)` from `dart:async`. Use it to satisfy `unawaited_futures`/`discarded_futures` where fire-and-forget is intended, and attach a `.catchError` or handle errors in the callee — an unawaited future's error becomes an uncaught async error.

## `async` / `await` semantics

- An `async` function returns a `Future` immediately and runs synchronously up to the first `await`.
- `await` on a non-future value still yields to the microtask queue.
- `async` functions never `throw` synchronously; they return a failed future. Wrapping a call in `try` without `await` catches nothing:

```dart
// Before — the error escapes: `f()` returns a failed future, it does not throw here
try { f(); } catch (e) { handle(e); }

// After
try { await f(); } catch (e) { handle(e); }
```

- `return` inside `try` with a `finally` still runs the `finally` before the future completes.

## Streams

| Concept | Single-subscription | Broadcast |
|---|---|---|
| Listeners | exactly one, ever | many, concurrently |
| Buffering before `listen` | yes | no — events before the first listener are lost |
| Pause/resume | supported; the source is told | `isPaused` per subscription; no `onPause`/`onResume` on the controller |
| Created by | `StreamController<T>()`, `async*`, file/socket reads | `StreamController<T>.broadcast()`, `stream.asBroadcastStream()` |
| Re-`listen` after cancel | error | allowed |

`StreamController({void onListen()?, void onPause()?, void onResume()?, FutureOr<void> onCancel()?, bool sync = false})`; `StreamController.broadcast` accepts only `onListen`, `onCancel`, and `sync`.

`sync: true` delivers events synchronously from `add()`. It is a footgun — reentrancy, events delivered mid-mutation — and belongs only in forwarding controllers that never originate events. Default to `sync: false`.

### Controller hygiene

```dart
void start(Stream<RawEvent> source) {
  _sub?.cancel();
  _sub = source.listen(
    (e) { if (!_controller.isClosed) _controller.add(Note.from(e)); },
    onError: _controller.addError,
    onDone: () => unawaited(_controller.close()),
    cancelOnError: false,
  );
}

Future<void> dispose() async {
  await _sub?.cancel();   // cancel before closing, always
  _sub = null;
  await _controller.close();
}
```

Checklist:

- `add`/`addError` after `close()` throws `StateError`. Guard with `isClosed` when the producer can outlive disposal.
- A single-subscription controller with no listener buffers every event in memory forever.
- `await controller.close()` completes only after the `done` event is delivered; on a single-subscription controller with no listener it never completes. Do not block `dispose` on it in that case.
- `onError` on `listen` takes `Function` — use `(Object e, StackTrace st)` so the stack trace is not lost.
- `cancelOnError: true` cancels the subscription on the first error; the default `false` keeps listening.
- Enable `cancel_subscriptions` and `close_sinks`.

### `async*` and `await for`

```dart
Stream<int> countdown(int from) async* {
  for (var i = from; i > 0; i--) {
    await Future<void>.delayed(const Duration(seconds: 1));
    yield i;
  }
  yield* finale();
}
```

- An `async*` generator is lazy: the body does not start until someone listens, and it pauses when the subscription pauses.
- `await for (final x in stream)` subscribes, and **never completes** for a stream that never closes. Never `await for` over a broadcast stream of app events in a method whose caller expects it to return.
- `break` inside `await for` cancels the subscription. An exception propagating out of the loop also cancels it.
- `yield*` delegates to another stream and forwards its errors.
- A `return` in `async*` ends the stream; `throw` sends an error event and ends it.

### Useful `Stream` transformers

`map`, `where`, `expand`, `asyncMap` (serialised, back-pressured), `asyncExpand`, `distinct`, `take`, `takeWhile`, `skip`, `timeout`, `handleError(f, {test})`, `transform(StreamTransformer)`, `asBroadcastStream`. `dart:async` has no debounce or throttle — write one with a `Timer`, or use `package:rxdart`.

## `Completer`

```dart
final completer = Completer<Note>();
channel.setHandler((note) {
  if (!completer.isCompleted) completer.complete(note);
});
return completer.future;
```

Rules: check `isCompleted` before completing, complete errors with `completeError(error, stackTrace)`, and never use a `Completer` where `async`/`await` would do. `Completer.sync()` exists and should be avoided for the same reason as `sync: true` controllers.

## `Timer` and `scheduleMicrotask`

```dart
final timer = Timer(const Duration(seconds: 5), _fire)..cancel();
final periodic = Timer.periodic(const Duration(seconds: 1), (t) {
  if (done) t.cancel();
});
```

A `Timer` is the only cancellable primitive here — prefer it to `Future.delayed` for anything that might need to stop. `Timer.periodic` does not wait for the callback to finish; an `async` callback can overlap with itself.

`scheduleMicrotask(f)` puts `f` at the head of the queue, before any timer or I/O. Use it essentially never in app code; it is how you starve the event loop.

## Zones

`Zone` is the ambient context that async errors propagate to. In practice you need three things:

- `runZonedGuarded(body, (error, stack) { ... })` catches uncaught async errors raised inside `body`. `Zone.current.handleUncaughtError` is what an unawaited failed future hits.
- `Zone.current[#key]` / `runZoned(zoneValues: {...})` is the closest Dart has to a request-scoped context.
- Overriding `print` via `ZoneSpecification(print: ...)` is the supported way to capture log output in tests.

Error handoff to Flutter's own handlers is in `errors.md`.

## Isolates

Dart has no shared-memory threads. Heavy CPU work goes to another isolate.

```dart
final parsed = await Isolate.run(() => jsonDecode(bigPayload) as Map<String, Object?>);
```

`static Future<R> run<R>(FutureOr<R> computation(), {String? debugName})` from `dart:isolate`. The closure and its result must be sendable; a closure that captures a `BuildContext`, a socket, an open file, or anything with a native handle fails at run time.

| Need | Use |
|---|---|
| One-off CPU work, Dart-only | `Isolate.run` |
| One-off CPU work in Flutter, with a top-level or static function | `compute(fn, message)` from `package:flutter/foundation.dart` |
| Long-lived worker with two-way messaging | `Isolate.spawn` + `ReceivePort`/`SendPort` |
| Calling into the Flutter engine or plugins | the root isolate only — background isolates need `BackgroundIsolateBinaryMessenger` (verify against the API docs before asserting the exact setup) |

Sendable across isolates: primitives, `String`, `List`/`Map`/`Set` of sendable values, records of sendable values, `SendPort`, `TransferableTypedData`, and (since isolate groups) most plain Dart objects by deep copy. Not sendable: closures capturing non-sendable state, native resources, `dart:ui` handles.

Provider-level async state (`AsyncValue`, `ref.watch` on a future) is `riverpod-pro`; `FutureBuilder`/`StreamBuilder` rebuild semantics are `flutter-widgets-pro`.

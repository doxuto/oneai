# Async, timers, streams, and time

Read this when a test hangs, when it fails with "A Timer is still pending even after the widget tree was disposed", or when the thing under test is a debounce, a retry schedule, a stream, or anything that reads the wall clock. The governing fact: inside `testWidgets` and inside `fakeAsync`, time does not pass unless you advance it.

## Two fake-time environments

| Environment | Entry point | Advance time with | Use for |
|---|---|---|---|
| Widget tests | `testWidgets` | `await tester.pump(duration)` | anything with a widget tree |
| Plain Dart | `fakeAsync((async) { ... })` from `package:fake_async` 1.3.3 | `async.elapse(duration)` | repositories, notifiers, debouncers, retry policies |

`fakeAsync` also installs a fake `clock` from `package:clock`, so `clock.now()` inside the callback tracks the elapsed fake time. `DateTime.now()` does not — that is the reason to inject the clock.

## `fakeAsync`

```dart
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  test('retries three times with exponential backoff', () {
    fakeAsync((async) {
      final attempts = <Duration>[];
      final start = clock.now();

      final future = retry(
        () async {
          attempts.add(clock.now().difference(start));
          throw const SocketException('offline');
        },
        maxAttempts: 3,
      );

      Object? error;
      future.catchError((Object e) { error = e; });

      async.elapse(const Duration(seconds: 10));

      expect(attempts, [
        Duration.zero,
        const Duration(milliseconds: 200),
        const Duration(milliseconds: 600),
      ]);
      expect(error, isA<SocketException>());
    });
  });
}
```

| `FakeAsync` member | Effect |
|---|---|
| `elapse(Duration d)` | Advances the clock, running timers and microtasks as their due time passes |
| `elapseBlocking(Duration d)` | Advances the clock **without** running timers — simulates a synchronous block |
| `flushMicrotasks()` | Drains the microtask queue without advancing time |
| `flushTimers({Duration timeout = const Duration(hours: 1), bool flushPeriodicTimers = true})` | Runs pending timers until none remain or `timeout` elapses |
| `pendingTimers` | The timers still scheduled — assert it is empty to prove there is no leak |
| `pendingTimersDebugString` | Human-readable list with creation stack traces |
| `periodicTimerCount`, `nonPeriodicTimerCount`, `microtaskCount` | Counters for leak assertions |
| `run(callback)` | Lower-level form; `fakeAsync(...)` is the wrapper you want |

Two rules that catch most misuse:

- **Never `await` inside the `fakeAsync` callback.** The callback is synchronous. `await` suspends until a real event loop turn that never comes, and the test times out. Capture the future, elapse, then inspect it.
- **`elapse` will not complete a future that depends on real I/O.** `fakeAsync` fakes timers and microtasks, not sockets or files.

Asserting no timer leaked:

```dart
fakeAsync((async) {
  final controller = DebounceController(const Duration(milliseconds: 300));
  controller.dispose();
  async.flushMicrotasks();

  expect(async.pendingTimers, isEmpty, reason: async.pendingTimersDebugString);
});
```

## "A Timer is still pending even after the widget tree was disposed"

`AutomatedTestWidgetsFlutterBinding` fails a test whose fake clock still has a scheduled timer when the body returns. It is almost always a real bug, not a test artefact.

| Cause | Fix |
|---|---|
| `Timer` created in `initState` and not cancelled in `dispose` | Cancel it; the test is correct |
| Debounce timer still armed after the last keystroke | `await tester.pump(debounceDuration)` at the end of the test, or cancel on dispose |
| `AnimationController` not disposed | Dispose it; `SingleTickerProviderStateMixin` asserts this too |
| A package that schedules a periodic timer on construction | Advance past it, or fake the package behind an interface |
| A snack bar or tooltip still showing | `await tester.pump(const Duration(seconds: 5))` to let it expire |

The wrong fix is `tester.binding.delayed(...)` or wrapping the whole body in `runAsync` to make the failure go away. Both hide the leak.

## `tester.runAsync`

```dart
Future<T?> runAsync<T>(
  Future<T> Function() callback, {
  Duration additionalTime = const Duration(milliseconds: 1000),
})
```

Inside `runAsync`, the binding switches to the **real** event loop so genuinely asynchronous work can complete. Use it for:

- decoding a real image (`precacheImage`, `NetworkImage` with a fake HTTP override)
- reading a real asset through `rootBundle`
- a package that insists on a real `Future.delayed`
- anything that talks to a real file

```dart
testWidgets('renders the bundled logo', (tester) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(const MaterialApp(home: LogoHeader()));
    await tester.pumpAndSettle();
  });

  expect(find.byType(Image), findsOneWidget);
});
```

Constraints: `pumpAndSettle` is not allowed to be called from *outside* `runAsync` while a real future is in flight, `runAsync` returns `null` if the callback throws a test failure, and nesting `runAsync` calls is an error. Keep the block as small as possible — everything inside it runs in real time, which is how a suite silently becomes slow.

## Streams

`flutter_test` re-exports the `package:test` stream matchers, so `emits` and friends are available without an extra import.

| Matcher | Matches |
|---|---|
| `emits(m)` | the next event matches `m` |
| `emitsInOrder([...])` | each matcher in turn; a plain value is an equality matcher |
| `emitsInAnyOrder([...])` | the same set, any order |
| `emitsThrough(m)` | some event matches `m`, skipping earlier ones |
| `emitsDone` | the stream closes |
| `emitsError(m)` | the next event is an error matching `m` |
| `neverEmits(m)` | nothing matching `m` before the stream closes |
| `mayEmit(m)` / `mayEmitMultiple(m)` | optional events, for interleaving |

```dart
test('search debounces to one query per pause', () {
  fakeAsync((async) {
    final controller = SearchController();

    expectLater(
      controller.queries,
      emitsInOrder(['fl', emitsDone]),
    );

    controller
      ..type('f')
      ..type('fl');
    async.elapse(const Duration(milliseconds: 300));
    controller.close();
    async.flushMicrotasks();
  });
});
```

`expectLater` on a stream subscribes immediately, which matters for a single-subscription stream: call it *before* the events are produced. For a broadcast stream, subscribe first or the early events are lost.

`neverEmits` only resolves when the stream closes, so it needs a stream you can close — on an endless stream it will hang.

## `expectLater` on futures

```dart
await expectLater(repository.fetchAll(), completion(hasLength(2)));
await expectLater(repository.fetchAll(), throwsA(isA<TodoNotFound>()));
await expectLater(
  repository.fetchAll(),
  throwsA(isA<FirebaseException>().having((e) => e.code, 'code', 'permission-denied')),
);
```

`completion(matcher)` and `throwsA(matcher)` are the only correct forms for a future. `expect(await f, ...)` works too but loses the failure message when the future throws. `.having(...)` is how you assert on a field without writing a custom matcher, and it prints the field name in the failure.

Never write `expect(f, completes)` without `await`/`expectLater`: the test ends before the future resolves and the assertion is silently abandoned.

## Clock injection

Production code that calls `DateTime.now()` directly cannot be tested across a date boundary, a timezone, or a token expiry.

```dart
// Before
class Session {
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

// After
import 'package:clock/clock.dart';

class Session {
  bool get isExpired => clock.now().isAfter(expiresAt);
}
```

```dart
test('a session that expired one second ago is expired', () {
  withClock(Clock.fixed(DateTime.utc(2026, 9, 22, 12, 0, 0)), () {
    final session = Session(expiresAt: DateTime.utc(2026, 9, 22, 11, 59, 59));
    expect(session.isExpired, isTrue);
  });
});
```

`package:clock` 1.1.3 exposes the top-level `clock` getter, `withClock(Clock, callback)`, `Clock.fixed(DateTime)`, `clock.now()`, `clock.fromNow(...)` and `clock.stopwatch()`. `fakeAsync` installs its own clock automatically, so inside `fakeAsync` you get both fake timers and a fake `clock.now()` for free.

In a widget test, wrap the `pumpWidget` in `withClock` if the widget reads the clock during build. Riverpod apps should instead inject a clock provider and override it — see `riverpod-pro` → `references/testing.md`.

## Debounce and throttle

```dart
testWidgets('search fires once after the user stops typing', (tester) async {
  final api = FakeSearchApi();
  await tester.pumpApp(SearchPage(api: api));

  await tester.enterText(find.byType(TextField), 'f');
  await tester.pump(const Duration(milliseconds: 100));
  await tester.enterText(find.byType(TextField), 'fl');
  await tester.pump(const Duration(milliseconds: 100));
  await tester.enterText(find.byType(TextField), 'flu');

  expect(api.queries, isEmpty, reason: 'still inside the debounce window');

  await tester.pump(const Duration(milliseconds: 300));

  expect(api.queries, ['flu']);
});
```

For a throttle, assert the opposite shape: the *first* call goes through immediately and subsequent calls inside the window are dropped.

```dart
await tester.pump(const Duration(milliseconds: 299)); // just inside
expect(api.queries, isEmpty);
await tester.pump(const Duration(milliseconds: 1));   // boundary
expect(api.queries, ['flu']);
```

Testing the exact boundary — one tick before and one tick after — is what makes the test catch an off-by-one in the debounce implementation. A single `pump(const Duration(seconds: 1))` would pass against almost any duration.

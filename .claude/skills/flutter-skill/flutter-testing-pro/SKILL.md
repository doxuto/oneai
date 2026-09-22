---
name: flutter-testing-pro
description: Writes, reviews, and refactors Flutter test suites built on flutter_test, package:test, and integration_test. Use when reading, writing, or reviewing code that uses testWidgets, WidgetTester, pumpWidget, pump, pumpAndSettle, find.byType, findsOneWidget, matchesGoldenFile, fakeAsync, mocktail, mockito, IntegrationTestWidgetsFlutterBinding, or dart_test.yaml, or when the user mentions widget tests, golden tests, flaky tests, fakes, test coverage, --update-goldens, or a CI job that runs flutter test.
license: MIT
metadata:
  author: doxuto
  version: "1.0"
  targets: "Flutter 3.47.5, Dart 3.13.4, flutter_test and integration_test from the SDK, mocktail 1.0.5, mockito 5.8.1, fake_async 1.3.3, clock 1.1.3"
---

Write and review Flutter tests for correctness, determinism, and maintenance cost. Most broken Flutter test suites fail for one of three reasons: `pumpAndSettle` used where `pump` was meant, real time or real I/O leaking into a fake-async environment, and goldens generated on a machine that is not the one that verifies them. Report only genuine problems — do not nitpick or invent issues.

## Core principles

1. **A test asserts what a user can observe, not how the code is arranged.** Assert on rendered text, semantics, and returned values. A test that asserts a private method was called with three arguments breaks on every refactor and catches nothing; `verify(() => mock.save(any())).called(1)` is the smell.
2. **`pump` and `pumpAndSettle` are different tools and the wrong one hangs.** `pump()` produces exactly one frame. `pump(duration)` advances the fake clock and produces one frame. `pumpAndSettle()` repeats frames until no more are scheduled, and throws once its `timeout` (default ten minutes) elapses. A repeating animation, an indeterminate `CircularProgressIndicator`, or a live `Ticker` never settles.
3. **Widget tests run in fake time with a fake network and no real I/O.** `Timer`, `Future.delayed`, and `DateTime.now` via `package:clock` are all under the test's control. Anything that genuinely needs the event loop — an `Image` decode, a real file read — must be wrapped in `tester.runAsync`.
4. **Hand-written fakes are the default; mocks are the exception.** A `FakeTodoRepository implements TodoRepository` is thirty lines, reads like documentation, and fails to compile when the interface changes. Reach for `mocktail` only when you need call-order or argument assertions that a fake cannot express cheaply.
5. **Never mock a type you do not own.** `class MockFirebaseFirestore extends Mock implements FirebaseFirestore` encodes your guess about someone else's behaviour. Put an interface you own in front of it and fake that.
6. **A golden is a contract with a maintenance bill.** Goldens are byte-exact image comparisons; they differ across host platform, font availability, and engine version. Generate and verify them in one environment, keep them few, and delete any golden that is re-baselined without anyone reading the diff.
7. **A flaky test is a defective test, not a defective CI runner.** Retries hide the defect and keep the cost. Find the shared state, the real timer, or the unawaited future and remove it.

## Review process

1. Check directory layout, file naming, `group`/`setUp`/`addTearDown` structure, tags and `dart_test.yaml` using `references/test-layout.md`.
2. Check that each piece of code is covered by the cheapest test kind that can catch its bugs using `references/what-to-test.md`.
3. Check `pumpWidget`, pump semantics, finders, matchers and interactions using `references/widget-tests.md`.
4. Check timers, streams, clock injection, `fakeAsync` and `tester.runAsync` using `references/async-and-time.md`.
5. Check fakes, mocks, HTTP and platform-channel substitution using `references/test-doubles.md`.
6. Check golden file strategy, fonts, and re-baselining discipline using `references/golden-tests.md`.
7. Check `integration_test` setup, flow scope, and performance tracing using `references/integration-tests.md`.
8. Check determinism, ordering dependence, sharding and the CI workflow using `references/flakiness-and-ci.md`.
9. Flag any removed, renamed, or hallucinated test API using `references/common-mistakes.md`.

If doing a partial review, load only the relevant reference files.

## Core instructions

- Import Material from `package:material_ui/material_ui.dart` and Cupertino from `package:cupertino_ui/cupertino_ui.dart`. Flutter 3.47 decoupled both out of the SDK; `package:flutter/material.dart` still compiles but its classes are *distinct types* from the package's, so mixing the two produces "argument type X is not the type X" errors. Migrate with `dart fix --apply --code=migrate_design_widgets`. See `flutter-widgets-pro` → `references/material3-theming.md`.
- `flutter test` collects files under `test/` whose names end in `_test.dart` and that declare `void main()`. A helper file named `..._test.dart` with no tests fails the run; name helpers `*_helpers.dart` or put them in `test/support/`.
- Every `WidgetTester` method returns a `Future`. A missing `await` on `tester.tap`, `tester.pump`, or `tester.enterText` produces an assertion about a pending `TestAsyncUtils` guard, or worse, a test that passes for the wrong reason.
- Prefer `await tester.pump()` plus an explicit `pump(duration)` per animation step over `pumpAndSettle()`. Use `pumpAndSettle` only where the widget under test provably reaches a steady state; its return value is the frame count, and a zero-frame settle usually means the interaction never happened.
- Never call `pumpAndSettle` on a tree containing an indeterminate progress indicator, a `RepeatingTicker`-backed animation, or a `StreamBuilder` fed by `Stream.periodic`. Drive those with `pump(const Duration(milliseconds: 16))` a fixed number of times.
- Find widgets by `find.byKey(const ValueKey('submit'))` for controls the test drives and by `find.text(...)` for content the user reads. `find.byType` is acceptable for one-of-a-kind widgets and brittle everywhere else.
- Use `findsOneWidget` / `findsNothing` / `findsNWidgets(n)` / `findsAtLeastNWidgets(n)` for widget finders, and the generic `findsOne` / `findsAny` / `findsExactly(n)` / `findsAtLeast(n)` when matching a non-widget `FinderBase` such as a semantics finder. All are current; none is deprecated.
- Set the test surface with `tester.view.physicalSize` and `tester.view.devicePixelRatio`, and text scale with `tester.platformDispatcher.textScaleFactorTestValue`. Always pair them with `addTearDown(tester.view.reset)` — these values are global to the binding and leak into the next test in the same file.
- `tester.binding.window` still exists but is deprecated in favour of `tester.view` and `tester.platformDispatcher`; treat any `window.physicalSizeTestValue` / `window.textScaleFactorTestValue` in a diff as a finding.
- Wrap real asynchronous work — network calls you deliberately allow, `rootBundle` reads, image decoding — in `await tester.runAsync(() async { ... })`. Outside it, the binding's clock never advances on its own and the future never completes.
- Inject `DateTime.now()` through `package:clock` (`clock.now()` in production code, `withClock(Clock.fixed(...), () { ... })` in the test). Direct `DateTime.now()` makes date-boundary bugs untestable and reproducible only at midnight.
- Test a debounce, throttle, or retry schedule with `fakeAsync` from `package:fake_async` for plain Dart, and with `tester.pump(duration)` inside a widget test. `async.elapse(...)` then `expect(...)`; an unconsumed timer at the end of `fakeAsync` is a leak the test should assert on via `async.pendingTimers`.
- Replace HTTP with `MockClient` from `package:http/testing.dart` (`MockClient((request) async => http.Response('{}', 200))`), not by mocking `http.Client`. Replace platform channels with `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, handler)` and clear it by passing `null` in `addTearDown`.
- Seed `SharedPreferences` with `SharedPreferences.setMockInitialValues({...})` inside `setUp`. For the newer `SharedPreferencesAsync` API, assign `SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty()` instead.
- Declare golden tests behind a tag (`@Tags(['golden'])` at the top of the file, plus a `tags:` entry in `dart_test.yaml`) so `flutter test --exclude-tags golden` is available to contributors on a different platform.
- Write goldens as `await expectLater(find.byType(MyCard), matchesGoldenFile('goldens/my_card.png'))`. Re-baseline with `flutter test --update-goldens`, and never commit a re-baselined PNG without looking at the diff.
- Keep `integration_test/` small. One `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` per entry point, a handful of end-to-end flows, and nothing that a widget test could have caught.
- Measure coverage with `flutter test --coverage` (output `coverage/lcov.info`), then strip generated files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `firebase_options.dart`) before reporting, either with `--coverage-package` or `lcov --remove`. Coverage that counts generated code is a number about the generator.
- Do not paper over flakiness with `retry:` in `dart_test.yaml` or `--total-shards` reshuffling. Fix the shared state; reserve `retry` for genuinely external integration suites.
- Provider-level tests — `ProviderContainer.test()`, `overrideWith`, `overrideWithBuild`, awaiting `.future` — belong to `riverpod-pro` → `references/testing.md`. Load that instead of restating container mechanics here.

## Canonical example

`test/support/pump_app.dart`:

```dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// One place that knows how a page is mounted for a test: the same
/// MaterialApp, the same theme, the same ProviderScope overrides shape.
extension PumpApp on WidgetTester {
  Future<void> pumpApp(
    Widget child, {
    List<Override> overrides = const [],
    Size surface = const Size(390, 844), // iPhone 15 logical size
  }) async {
    view.physicalSize = surface * view.devicePixelRatio;
    addTearDown(view.reset);

    await pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: child,
        ),
      ),
    );
  }
}
```

`test/support/fake_todo_repository.dart`:

```dart
import 'dart:io';

import 'package:my_app/features/todos/data/todo_repository.dart';

/// Hand-written, not generated. It compiles against the real interface, so a
/// signature change breaks the fake instead of silently stubbing the old one.
class FakeTodoRepository implements TodoRepository {
  FakeTodoRepository({List<Todo> todos = const []}) : _todos = [...todos];

  final List<Todo> _todos;
  bool failNextWrite = false;
  int fetchCount = 0;

  @override
  Future<List<Todo>> fetchAll() async {
    fetchCount++;
    return List.unmodifiable(_todos);
  }

  @override
  Future<void> setDone(String id, {required bool done}) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw const SocketException('offline');
    }
    final i = _todos.indexWhere((t) => t.id == id);
    _todos[i] = _todos[i].copyWith(done: done);
  }
}
```

`test/features/todos/todo_list_page_test.dart`:

```dart
@Tags(['widget'])
library;

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_app/features/todos/data/todo_repository.dart';
import 'package:my_app/features/todos/presentation/todo_list_page.dart';

import '../../support/fake_todo_repository.dart';
import '../../support/pump_app.dart';

void main() {
  late FakeTodoRepository repository;

  setUp(() {
    repository = FakeTodoRepository(
      todos: const [
        Todo(id: '1', title: 'Buy milk', done: false),
        Todo(id: '2', title: 'Call Ana', done: true),
      ],
    );
  });

  group('TodoListPage', () {
    testWidgets('renders one tile per todo once loading resolves', (tester) async {
      await tester.pumpApp(
        const TodoListPage(),
        overrides: [todoRepositoryProvider.overrideWithValue(repository)],
      );

      // First frame is the loading state: the future has not completed yet.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pump(); // let the already-completed future flush

      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      expect(find.text('Buy milk'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('tapping a tile writes through to the repository', (tester) async {
      await tester.pumpApp(
        const TodoListPage(),
        overrides: [todoRepositoryProvider.overrideWithValue(repository)],
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(CheckboxListTile, 'Buy milk'));
      await tester.pump();

      final checkbox = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Buy milk'),
      );
      expect(checkbox.value, isTrue);
    });

    testWidgets('a failed write rolls back and shows a snack bar', (tester) async {
      repository.failNextWrite = true;

      await tester.pumpApp(
        const TodoListPage(),
        overrides: [todoRepositoryProvider.overrideWithValue(repository)],
      );
      await tester.pump();

      await tester.tap(find.widgetWithText(CheckboxListTile, 'Buy milk'));
      await tester.pump(); // optimistic update + failure
      await tester.pump(); // SnackBar enters the tree

      expect(find.textContaining('Could not save'), findsOneWidget);
      final checkbox = tester.widget<CheckboxListTile>(
        find.widgetWithText(CheckboxListTile, 'Buy milk'),
      );
      expect(checkbox.value, isFalse); // rolled back
    });

    testWidgets('survives a 2.0 text scale without overflowing', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.platformDispatcher.clearAllTestValues);

      await tester.pumpApp(
        const TodoListPage(),
        overrides: [todoRepositoryProvider.overrideWithValue(repository)],
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}
```

`dart_test.yaml` at the package root:

```yaml
tags:
  widget:
  golden:
    # Goldens are rendered by one platform only; see references/golden-tests.md.
  integration:
    timeout: 2x
```

Run it with `flutter test`, `flutter test --exclude-tags golden`, or `flutter test --coverage --reporter github` in CI.

The page under test, its keys and its layout belong to `flutter-widgets-pro`; the provider overrides used above are owned by `riverpod-pro` → `references/testing.md`.

## Output format

If the user asks for a review, organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated.
3. Show a brief before/after code fix.

Skip files with no issues. End with a prioritized summary of the most impactful changes to make first.

If the user asks you to write or improve tests, follow the same rules but make the changes directly instead of returning a findings report.

Example output:

### test/features/todos/todo_list_page_test.dart

**Line 18: `pumpAndSettle` on a tree with an indeterminate progress indicator — this test hangs for ten minutes and then fails with a timeout, not an assertion.**

```dart
// Before
await tester.pumpWidget(const App());
await tester.pumpAndSettle();

// After
await tester.pumpWidget(const App());
await tester.pump(); // one frame: enough for an already-completed future
```

**Line 31: surface size set without a teardown — the next test in this file inherits a 320x480 view and fails for an unrelated reason.**

```dart
// Before
tester.view.physicalSize = const Size(320, 480);

// After
tester.view.physicalSize = const Size(320, 480);
addTearDown(tester.view.reset);
```

### test/data/api_client_test.dart

**Line 9: real `http.Client` used in a unit test — the suite depends on network reachability and on someone else's staging environment.**

```dart
// Before
final client = ApiClient(http.Client());

// After
final client = ApiClient(
  MockClient((request) async => http.Response('{"items":[]}', 200)),
);
```

### Summary

1. **Hang (high):** `pumpAndSettle` at line 18 makes the whole suite take ten minutes to fail.
2. **Cross-test leakage (high):** unreset view size at line 31 will fail a sibling test intermittently.
3. **Flake (high):** live network at `api_client_test.dart:9` — the most common cause of red CI on an unrelated PR.

End of example.

## References

- `references/test-layout.md` — `test/` vs `integration_test/`, mirroring `lib/`, `_test.dart` naming, `group`/`test`/`setUp`/`tearDown`/`setUpAll`/`addTearDown`, `testWidgets`, `@Tags` and `dart_test.yaml` (`tags`, `include_tags`, `exclude_tags`, `timeout`, `retry`, `concurrency`, `presets`), `flutter test` flags (`--coverage`, `--coverage-package`, `--tags`, `--exclude-tags`, `--update-goldens`, `--concurrency`, `--reporter`, `--total-shards`, `--test-randomize-ordering-seed`), excluding generated files from coverage.
- `references/what-to-test.md` — decision table from code kind (pure function, notifier, repository, widget, navigation flow) to test kind, the Flutter-shaped test pyramid, what not to test (framework widgets, generated code, private methods, `build` internals), turning a bug report into a regression test, coverage targets that mean something.
- `references/widget-tests.md` — `WidgetTester`, `pumpWidget`, `pump` vs `pump(duration)` vs `pumpAndSettle` and when each hangs, `pumpFrames`, finders table (`byType`, `byKey`, `text`, `textContaining`, `widgetWithText`, `widgetWithIcon`, `descendant`, `ancestor`, `byWidgetPredicate`, `bySemanticsLabel`, `byTooltip`), matchers table (`findsOneWidget`, `findsNothing`, `findsNWidgets`, `findsAtLeastNWidgets`, `findsOne`, `findsExactly`, `findsAtLeast`), `tap`/`enterText`/`drag`/`fling`/`longPress`/`scrollUntilVisible`, `tester.view` and `tester.platformDispatcher`, `setSurfaceSize`, `takeException`, `expectLater` with `matchesGoldenFile`.
- `references/async-and-time.md` — `fakeAsync`/`FakeAsync`, `elapse`, `elapseBlocking`, `flushMicrotasks`, `flushTimers`, `pendingTimers`, `tester.runAsync`, "A Timer is still pending" failures, `pumpAndSettle` timeouts, stream matchers (`emits`, `emitsInOrder`, `emitsDone`, `neverEmits`, `emitsThrough`, `emitsError`), `expectLater` on futures with `completion`/`throwsA`, clock injection with `package:clock` and `withClock`, debounce and throttle tests.
- `references/test-doubles.md` — hand-written fakes as the default, `Fake` from `flutter_test`, `mocktail` 1.0.5 vs `mockito` 5.8.1 and when either is warranted, `registerFallbackValue`, `@GenerateNiceMocks`, faking a repository behind an interface, not mocking types you do not own, `MockClient` and `MockClient.streaming` from `package:http/testing.dart`, platform channels via `TestDefaultBinaryMessengerBinding` and `setMockMethodCallHandler`/`setMockStreamHandler`, `SharedPreferences.setMockInitialValues` and `InMemorySharedPreferencesAsync`.
- `references/golden-tests.md` — `matchesGoldenFile(key, {version})`, `goldenFileComparator`, `LocalFileComparator`, `autoUpdateGoldenFiles`, why goldens differ across machines, CI-only and one-platform rules, Docker-pinned baselines, `golden_toolkit` discontinued status and what replaced it, the `FlutterTest` default font and loading real fonts with `FontLoader`, `--update-goldens`, reviewing diffs, when a golden earns its cost.
- `references/integration-tests.md` — the `integration_test` SDK package, `IntegrationTestWidgetsFlutterBinding.ensureInitialized()`, writing a flow test, running on device and emulator with `flutter test integration_test`, `flutter drive --driver --target` and `integrationDriver()` for screenshots and web, `takeScreenshot`, `convertFlutterSurfaceToImage`, `traceAction` and `watchPerformance` for performance traces, `reportData`, what belongs here versus in a widget test.
- `references/flakiness-and-ci.md` — the recurring causes of flaky Flutter tests and the fix for each, `pumpAndSettle` misuse, real network and real time, leaked binding state, ordering dependence and `--test-randomize-ordering-seed`, sharding with `--total-shards`/`--shard-index`, when `retry` is legitimate, a GitHub Actions job for format + analyze + test + coverage, coverage reporting and gating a PR.
- `references/common-mistakes.md` — removed, deprecated, and hallucinated test APIs with the correct replacement: `binding.window`, `TestWindow`, `textScaleFactorTestValue` placement, `findsAtLeast` vs `findsAtLeastNWidgets`, `MockNavigatorObserver`, `tester.pumpAndSettleUntil`, `flutter_driver` leftovers, `golden_toolkit` helpers, `setMockMethodCallHandler` on `MethodChannel`.

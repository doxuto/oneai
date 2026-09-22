# Flakiness and CI

Read this when a test passes locally and fails on CI, when a suite fails once in twenty runs, or when setting up the workflow that gates a pull request. A flaky test is a defect in the test. Retries convert it from a visible defect into an invisible one.

## The recurring causes, and the fix for each

| Symptom | Cause | Fix |
|---|---|---|
| Test hangs then fails after ten minutes | `pumpAndSettle` on a tree with an indeterminate progress indicator or repeating animation | Fixed `pump(const Duration(milliseconds: 16))` loop, or `pumpFrames` |
| "A Timer is still pending even after the widget tree was disposed" | A `Timer`/`AnimationController` not cancelled in `dispose` | Fix the widget; advancing time in the test only hides it |
| Passes alone, fails in the suite | Binding state leaked: `tester.view.physicalSize`, `textScaleFactorTestValue`, a mock channel handler, `SharedPreferences` values | `addTearDown` for every global you set |
| Passes in one order, fails in another | Shared mutable fixture declared as a field of `main()` instead of built in `setUp` | Build every fixture in `setUp` |
| Fails only on CI | Different locale, timezone, screen size, or missing font | Pin `localeTestValue`, inject the clock, set `tester.view`, load fonts |
| Fails around midnight / month end | `DateTime.now()` in production code | `clock.now()` + `withClock`, see `async-and-time.md` |
| Fails when the network is slow | A real HTTP call in a unit or widget test | `MockClient`, see `test-doubles.md` |
| Intermittent off-by-one-frame assertion | Asserting immediately after `tap` without pumping | `await tester.pump()` before the expectation |
| Golden fails on CI only | Baseline generated on a different platform | One-platform or Docker-pinned policy, see `golden-tests.md` |
| Random ordering of a `Set`/`Map` in an assertion | Iteration order is not guaranteed across runs | Sort before comparing, or use `unorderedEquals` |
| `expect` inside an async callback never runs | The callback is never awaited | `expectLater`, or `completer.future` awaited in the test body |
| Integration test fails on a shared staging account | Another run mutated the same data | Per-run account, or emulator reset in `setUp` |

## Proving a test is order-dependent

```bash
flutter test --test-randomize-ordering-seed random
flutter test --test-randomize-ordering-seed 12345   # reproduce the failure
```

Randomisation applies within a file. If the failure only appears across files, the leak is process-global: a mock channel handler, `HttpOverrides.global`, a static singleton, or a `GetIt`-style service locator that was never reset.

```dart
// Before — one instance for the whole file; test 2 sees test 1's writes
void main() {
  final repository = FakeTodoRepository(todos: seedTodos);

  test('a', () async { await repository.setDone('1', done: true); ... });
  test('b', () async { expect(repository.writes, isEmpty); ... }); // fails
}

// After
void main() {
  late FakeTodoRepository repository;
  setUp(() => repository = FakeTodoRepository(todos: seedTodos));
  ...
}
```

Note `seedTodos` must itself be immutable (`const`), or the copy in `setUp` shares its elements.

## Retries and quarantine

`dart_test.yaml` supports `retry:` and `flutter test` honours it. Legitimate uses:

- an integration suite against a real backend, where a transient 503 is genuinely external
- a device-farm job where the device occasionally fails to install

Illegitimate uses: anything in `test/`. A retried widget test is a test that has told you it is broken and been overruled.

When a test cannot be fixed today:

```dart
testWidgets('flaky flow', (tester) async { ... },
    skip: 'https://github.com/acme/app/issues/812 — flaky since 3.47 upgrade');
```

A `skip` with an issue URL is honest. A `retry: 3` is not. `flutter test --run-skipped` lets the owner run it while working on the fix.

## Sharding

```bash
flutter test --total-shards 4 --shard-index 0
```

Shards split the *file* list, so a single slow file is a floor on wall time. Split that file before adding shards. Shards do not help with flakiness; they change which tests share a process, which occasionally *reveals* leakage that was previously masked.

## A GitHub Actions workflow

```yaml
name: ci

on:
  pull_request:
  push:
    branches: [main]

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  analyze-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.47.5
          channel: stable
          cache: true

      - run: flutter pub get

      - name: Format
        run: dart format --output=none --set-exit-if-changed .

      - name: Analyze
        run: flutter analyze --fatal-infos --fatal-warnings

      - name: Verify generated code is up to date
        run: |
          dart run build_runner build --delete-conflicting-outputs
          git diff --exit-code

      - name: Test
        run: >
          flutter test
          --coverage
          --exclude-tags golden
          --reporter github
          --file-reporter json:reports/tests.json

      - name: Strip generated files from coverage
        run: |
          sudo apt-get update && sudo apt-get install -y lcov
          lcov --remove coverage/lcov.info \
            '*/*.g.dart' '*/*.freezed.dart' '*/*.gr.dart' \
            '*/firebase_options.dart' '*/generated_plugin_registrant.dart' \
            -o coverage/lcov.info

      - uses: codecov/codecov-action@v4
        with:
          files: coverage/lcov.info
          fail_ci_if_error: true

      - if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: test-reports
          path: reports/

  goldens:
    runs-on: macos-latest        # the one platform that owns the baselines
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: 3.47.5
          channel: stable
          cache: true
      - run: flutter pub get
      - run: flutter test --tags golden --reporter github
      - if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: golden-failures
          path: '**/failures/**'
```

Points that matter:

- `--reporter github` emits workflow annotations, so a failure appears on the changed line rather than only in the log.
- `flutter-version` is pinned exactly. `channel: stable` alone lets an upstream release change golden output and layout on an unrelated PR.
- The `git diff --exit-code` step catches a stale `.g.dart` committed by someone who forgot `build_runner`. It is the cheapest check in the file.
- Golden failures upload `failures/` so the reviewer can see `_maskedDiff.png` without reproducing locally.
- Integration tests are deliberately absent from the PR gate; run them on merge to `main` and nightly, on a device farm.

## Coverage reporting and gating

- Compute coverage after stripping generated files, or the number describes the generator.
- Gate on **delta**, not absolute: "coverage must not decrease by more than 0.5%" passes a refactor that removes tested code and fails a feature added without tests. An absolute floor is met by testing getters.
- `--branch-coverage` is more informative than line coverage for null-check-heavy Dart, at some runtime cost.
- Do not gate on coverage for a repository that has no suite yet. Set the first gate at the current number and ratchet.

## Making CI fast enough that people read it

| Lever | Effect |
|---|---|
| `--exclude-tags golden` on the PR job | Removes the slowest and most platform-sensitive tests from the common path |
| `cache: true` on `flutter-action` | Saves the SDK download on every run |
| `concurrency` with `cancel-in-progress` | Stops three stale runs per force-push |
| Sharding | Only after the slowest single file is split |
| `--fail-fast` | Useful locally; unhelpful on CI, where you want the full list |

A PR gate over about ten minutes gets ignored, and an ignored gate is worse than no gate — it trains reviewers to merge red.

## The review checklist

Flag any of these in a diff:

- `pumpAndSettle()` with no comment, in a file that also renders a progress indicator
- a global (`tester.view`, `platformDispatcher`, a channel handler, `HttpOverrides.global`) set without a matching `addTearDown`
- a mutable fixture initialised at `main()` scope rather than in `setUp`
- `retry:` added to `dart_test.yaml` in the same commit as a failing test
- `await Future.delayed(...)` inside a test body
- `DateTime.now()` in code that a test asserts on
- a real `http.Client`, `FirebaseFirestore.instance`, or `SharedPreferences.getInstance()` reached from a unit or widget test
- a golden baseline changed with no visual explanation in the PR description

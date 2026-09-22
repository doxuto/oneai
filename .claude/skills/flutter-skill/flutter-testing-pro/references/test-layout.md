# Test layout, tags, and the `flutter test` command line

Read this when setting up a test suite, adding a new test file, or deciding how the CI job invokes the runner. Everything here was checked against the `flutter_tools` `test` command source, the `package:test` configuration reference, and api.flutter.dev on 2026-09-22.

## Directory layout

```
my_app/
  lib/
    features/todos/data/todo_repository.dart
    features/todos/application/todo_list.dart
    features/todos/presentation/todo_list_page.dart
  test/
    features/todos/data/todo_repository_test.dart
    features/todos/application/todo_list_test.dart
    features/todos/presentation/todo_list_page_test.dart
    features/todos/presentation/goldens/todo_list_page.png
    support/
      pump_app.dart
      fake_todo_repository.dart
      fixtures.dart
  integration_test/
    app_test.dart
    checkout_flow_test.dart
  test_driver/
    integration_test.dart
  dart_test.yaml
```

Rules:

- `test/` mirrors `lib/` path for path. A reviewer looking at `lib/a/b/c.dart` must be able to guess the test's path without searching.
- `flutter test` picks up files under `test/` ending in `_test.dart` that declare `void main()`. A support file accidentally named `fixtures_test.dart` fails the run with "No tests were found"; name support files `*_helpers.dart`, `fake_*.dart`, or park them under `test/support/`.
- Golden images live next to the test that produces them, in a `goldens/` subdirectory. `matchesGoldenFile` resolves a relative key against the test file's directory (`LocalFileComparator`), so a shared top-level `test/goldens/` folder needs `../../goldens/x.png` keys and is worse.
- `integration_test/` is a sibling of `test/`, never inside it: `flutter test` would otherwise try to run device tests on the host VM.
- `test_driver/integration_test.dart` exists only when you use `flutter drive` (web, or screenshots). See `integration-tests.md`.

## File naming and the unit of a test file

| Production file | Test file | What it holds |
|---|---|---|
| `todo_repository.dart` | `todo_repository_test.dart` | parsing, error mapping, retry policy |
| `todo_list.dart` (notifier) | `todo_list_test.dart` | state transitions, no widget tree |
| `todo_list_page.dart` | `todo_list_page_test.dart` | `testWidgets` for this page only |
| — | `goldens/todo_list_page.png` | baselines for the file above |

One production file per test file. A `test/all_test.dart` that imports everything defeats sharding and makes failures hard to locate.

## Structure inside a file

```dart
@Tags(['widget'])
library;

import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeClock clock;

  setUpAll(() {
    // Once per file. Expensive, process-wide setup only: font loading,
    // registerFallbackValue for mocktail.
  });

  setUp(() {
    // Once per test. Rebuild every piece of mutable state here — never
    // as a field initialiser at the top of main().
    clock = FakeClock();
  });

  tearDown(() {
    // Prefer addTearDown inside the test that created the resource.
  });

  group('TodoRepository', () {
    test('maps a 404 to TodoNotFound', () async { /* ... */ });

    group('when offline', () {
      setUp(() { /* nested: runs after the outer setUp */ });

      test('returns the cached list', () async { /* ... */ });
    });
  });
}
```

| Hook | Runs | Use for |
|---|---|---|
| `setUpAll` | once before the file's tests | font loading, `registerFallbackValue`, anything genuinely immutable |
| `setUp` | before every test, outer group first | rebuilding all mutable fixtures |
| `tearDown` | after every test, inner group first | releasing what `setUp` acquired |
| `tearDownAll` | once after the file | closing a process-wide resource |
| `addTearDown(cb)` | after the current test, LIFO | anything acquired *inside* a test — the only hook that keeps acquisition and release adjacent |

`addTearDown` is the one to reach for by default. `tester.view.reset`, `container.dispose`, `subscription.cancel`, and `setMockMethodCallHandler(channel, null)` all belong there.

Never initialise mutable state in a field declaration at the top of `main()`. It is created once for the whole file and every test after the first sees the previous test's mutations.

## `testWidgets` versus `test`

```dart
test('pure Dart, no binding', () { ... });                  // package:test
testWidgets('needs a widget tree', (tester) async { ... }); // flutter_test
```

`testWidgets` installs `AutomatedTestWidgetsFlutterBinding`, fake time, and a `WidgetTester`. It also accepts the same metadata as `test`:

```dart
testWidgets(
  'renders the empty state',
  (tester) async { /* ... */ },
  tags: ['golden'],
  skip: false,
  timeout: const Timeout(Duration(seconds: 30)),
  variant: const TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}),
);
```

`variant` re-runs the body once per value and is the correct way to cover platform-dependent widgets; `TargetPlatformVariant.all()`, `.only(...)`, `.desktop()` and `.mobile()` are the built-in sets.

## Tags

Tag at file level with an annotation on the library directive, or per test with the `tags:` argument:

```dart
@Tags(['golden'])
library;
```

Every tag must be declared in `dart_test.yaml` or the runner warns about an unrecognised tag.

```yaml
# dart_test.yaml — package root, next to pubspec.yaml
tags:
  unit:
  widget:
  golden:
    # Only the CI container renders these; contributors run --exclude-tags golden.
  integration:
    timeout: 2x

# Global defaults
timeout: 30s
```

| `dart_test.yaml` key | Meaning |
|---|---|
| `tags` | per-tag configuration; declaring a tag here silences the unknown-tag warning |
| `add_tags` | tags implied by other tags |
| `include_tags` / `exclude_tags` | default tag selectors for a plain `dart test` run |
| `timeout` | default per-test timeout: `30s`, `2x`, or `none` |
| `retry` | number of retries for a failing test — see `flakiness-and-ci.md` before using it |
| `concurrency` | default parallel suite count |
| `platforms` / `test_on` / `on_platform` / `define_platforms` | platform selection; mostly irrelevant to `flutter test` |
| `presets` | named bundles of the above, selected with `--preset` |

`flutter test` honours `dart_test.yaml`, but its own command-line flags are the ones documented below and they win.

## `flutter test` flags worth knowing

| Flag | Effect |
|---|---|
| `--coverage` | collect coverage; writes `coverage/lcov.info` |
| `--coverage-path <path>` | where to store coverage information |
| `--coverage-package <regex>` | restrict coverage to package names matching the regular expression (repeatable) |
| `--merge-coverage` | merge with `coverage/lcov.base.info` |
| `--branch-coverage` | also collect branch coverage |
| `--tags <selector>` / `-t` | run only tests matching the tag selector |
| `--exclude-tags <selector>` / `-x` | skip tests matching the selector |
| `--update-goldens` | `matchesGoldenFile` rewrites baselines instead of comparing |
| `--concurrency <n>` / `-j` | parallel test processes; ignored for integration tests |
| `--reporter <r>` | `compact`, `expanded`, `failures-only`, `github`, `json`, `silent` |
| `--file-reporter <r>:<path>` | write a second report to a file, e.g. `json:reports/tests.json` |
| `--timeout <t>` | default per-test timeout: seconds (`60s`), a multiplier (`2x`), or `none` |
| `--total-shards` / `--shard-index` | split the suite across CI machines |
| `--test-randomize-ordering-seed <n\|random>` | randomise order within a file to expose ordering dependence |
| `--name <regex>` / `--plain-name <substring>` | filter by test name |
| `--run-skipped` | run tests marked `skip:` |
| `--fail-fast` | stop at the first failure |
| `--dart-define` | compile-time constants, same as the build commands |

Use `--reporter github` in GitHub Actions: it emits workflow annotations so failures land on the diff rather than only in the log.

## Coverage that means something

```bash
flutter test --coverage
```

`coverage/lcov.info` counts every compiled library, including generated ones. Strip them before reporting:

```bash
# Option A: restrict collection (regex over package names)
flutter test --coverage --coverage-package 'my_app'

# Option B: filter the lcov afterwards (needs the lcov CLI)
lcov --remove coverage/lcov.info \
  '*/*.g.dart' '*/*.freezed.dart' '*/*.gr.dart' \
  '*/firebase_options.dart' '*/generated_plugin_registrant.dart' \
  -o coverage/lcov.info
genhtml coverage/lcov.info -o coverage/html
```

Files that should never count toward a coverage gate: generated serialisation, generated providers, generated routes, `firebase_options.dart`, and localisation output. A gate computed over those measures the generator, not the suite.

## Naming tests

A test name is read in a failure log with no surrounding context. Write it as a sentence about behaviour:

```dart
// Bad
test('test1', ...);
test('toggle', ...);

// Good
test('toggle rolls the todo back when the write fails', ...);
testWidgets('shows the empty state when the list is empty', ...);
```

The `group` name carries the subject, the `test` name carries the behaviour, so the concatenation reads as `TodoRepository maps a 404 to TodoNotFound`.

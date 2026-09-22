# Golden tests

Read this before adding a golden, and whenever a golden fails on CI but passes locally (or the reverse). A golden test is a byte-comparison of a rendered image against a checked-in PNG. That makes it the strongest assertion available about appearance and the most environment-sensitive test in the suite.

## The API

```dart
AsyncMatcher matchesGoldenFile(Object key, {int? version})
```

- `key` is a `String` or a `Uri`. Anything else throws `ArgumentError`.
- A relative key resolves against the **test file's directory**, because `flutter test` installs `LocalFileComparator`.
- `version` appends a number to the filename so historical baselines can coexist.
- It is an `AsyncMatcher`, so it needs `expectLater` and `await`.

```dart
await expectLater(
  find.byType(TodoCard),
  matchesGoldenFile('goldens/todo_card.png'),
);
```

The subject may be a `Finder`, a `Future<ui.Image>`, or a `ui.Image`. Given a `Finder`, the framework renders the nearest enclosing `RepaintBoundary`, which is often larger than the widget you meant. Wrap the subject explicitly:

```dart
await tester.pumpWidget(
  MaterialApp(
    home: Center(
      child: RepaintBoundary(
        child: TodoCard(todo: const Todo(id: '1', title: 'Buy milk', done: false)),
      ),
    ),
  ),
);
await expectLater(
  find.byType(RepaintBoundary).last,
  matchesGoldenFile('goldens/todo_card.png'),
);
```

## The comparator

| Symbol | Role |
|---|---|
| `goldenFileComparator` | Top-level `GoldenFileComparator` getter/setter. Swap it to change comparison policy. |
| `LocalFileComparator` | Installed by `flutter test`. Treats the key as a path relative to the test file. |
| `TrivialComparator` | The default under `flutter run`; prints a message and does nothing. |
| `autoUpdateGoldenFiles` | `bool` exported by `flutter_test`; `--update-goldens` sets it. |
| `GoldenFileComparator.compare(Uint8List imageBytes, Uri golden)` | Returns `true` on match |
| `GoldenFileComparator.update(Uri golden, Uint8List imageBytes)` | Writes a new baseline |
| `GoldenFileComparator.compareLists(List<int> test, List<int> master)` | Static pixel comparison returning a `ComparisonResult` |

A tolerant comparator is the usual escape hatch for antialiasing noise. It is a deliberate weakening of the test, so bound it:

```dart
// test/flutter_test_config.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';

class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile, {this.threshold = 0.005});
  final double threshold;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= threshold) return true;
    final error = await generateFailureOutput(result, golden, basedir);
    throw FlutterError(error);
  }
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  goldenFileComparator = _TolerantComparator(
    Uri.parse('${(goldenFileComparator as LocalFileComparator).basedir}test'),
  );
  await testMain();
}
```

A threshold above roughly 1% stops catching the regressions goldens exist for.

## Why goldens differ across machines

| Cause | Effect | Mitigation |
|---|---|---|
| Host platform (macOS vs Linux vs Windows) | Different text rasterisation and antialiasing | Generate on one platform only |
| Flutter/engine version | Layout and shader changes between releases | Pin the Flutter version in CI and in `fvm`/`.tool-versions` |
| Font availability | A missing family silently falls back to `FlutterTest` | Load fonts explicitly (below) |
| `devicePixelRatio` | Different bitmap size | Set `tester.view.devicePixelRatio` in the test |
| Locale / text direction | Different line breaks | Pin `localeTestValue` |
| Impeller vs Skia | Different rasteriser | Irrelevant for widget tests (host CPU rendering), relevant for `flutter drive` screenshots |

The consequence: **there is no way to make goldens match across heterogeneous developer machines.** Every team converges on one of three policies.

| Policy | How | Cost |
|---|---|---|
| CI-only goldens | Tag them `golden`, run `flutter test --exclude-tags golden` locally, verify and re-baseline on CI | Contributors cannot iterate on visuals locally |
| One-platform rule | "Goldens are generated on macOS arm64 only"; CI runs the same image | Requires everyone who edits visuals to have that machine |
| Docker-pinned | A container with a pinned Flutter version and a font set; `docker run ... flutter test --update-goldens` | Slowest loop, most reproducible |

Docker-pinned is the only one that survives a mixed team. Whichever you pick, write it in the repository README — a golden failure with no documented policy costs an afternoon every time a new contributor arrives.

## Fonts

The default font in a Flutter test is **`FlutterTest`**, not Ahem. It has 1024 units per em, an ascent of 0.75em and a descent of 0.25em, and renders every glyph as a filled box. Any `fontFamily` that is not registered in the test isolate silently falls back to it — so a golden generated without loading your brand font is a picture of boxes, and it will keep passing.

Load real fonts with `FontLoader`:

```dart
// test/support/load_fonts.dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> loadAppFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final loader = FontLoader('Inter');
  for (final path in ['fonts/Inter-Regular.ttf', 'fonts/Inter-Bold.ttf']) {
    loader.addFont(Future.value(File(path).readAsBytesSync().buffer.asByteData()));
  }
  await loader.load();
}
```

Call it from `setUpAll` in each golden file, or once from `test/flutter_test_config.dart` so it applies package-wide. Icon fonts (`MaterialIcons`, `CupertinoIcons`) are bundled with the framework and available in tests without loading.

## `golden_toolkit` is discontinued

`golden_toolkit` (last release 0.15.0, February 2023) is marked **discontinued** on pub.dev. Do not add it to a new project, and treat `loadAppFonts()`, `testGoldens()`, `GoldenBuilder`, `multiScreenGolden()` and `DeviceBuilder` in an existing project as code to migrate off.

| `golden_toolkit` | Replacement |
|---|---|
| `loadAppFonts()` | a `FontLoader` helper as above |
| `testGoldens(...)` | plain `testWidgets` with a `@Tags(['golden'])` library annotation |
| `GoldenBuilder.grid/column` | build the grid yourself in a `Column`/`Wrap` and take one golden of it |
| `multiScreenGolden(...)` | a loop over sizes setting `tester.view.physicalSize`, one `matchesGoldenFile` per size |
| `DeviceBuilder` | the same loop, with a named record per device |

```dart
const _devices = [
  (name: 'phone', size: Size(390, 844), ratio: 3.0),
  (name: 'tablet', size: Size(834, 1194), ratio: 2.0),
];

for (final device in _devices) {
  testWidgets('todo card — ${device.name}', (tester) async {
    tester.view.physicalSize = device.size * device.ratio;
    tester.view.devicePixelRatio = device.ratio;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: TodoCardDemo()));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(TodoCardDemo),
      matchesGoldenFile('goldens/todo_card_${device.name}.png'),
    );
  });
}
```

`alchemist` is the community package most often adopted in its place; verify its current status on pub.dev before recommending it, since the same fate is possible.

## Re-baselining

```bash
flutter test --update-goldens                          # every golden in the package
flutter test --update-goldens test/ui/todo_card_test.dart
flutter test --update-goldens --tags golden
```

`--update-goldens` sets `autoUpdateGoldenFiles`, and `MatchesGoldenFile` calls `update()` instead of `compare()`. It always "passes", which is exactly why it must never run in the verification job.

Review discipline:

1. A PR that changes a golden PNG must say in its description what changed visually and why.
2. Look at the rendered image in the PR diff, not just the file-changed count. GitHub shows PNG diffs side by side.
3. On failure, the comparator writes `failures/<name>_testImage.png`, `_masterImage.png`, `_isolatedDiff.png` and `_maskedDiff.png` next to the golden. Attach `_maskedDiff.png` when the change is being argued about.
4. Never re-baseline "to make CI green". A golden that changed without an intended visual change is the test reporting a regression.

## When a golden earns its cost

Add one when:

- the component is reused in three or more places and a theme change would silently restyle all of them
- the appearance itself is the contract (a chart, a badge, a print/PDF layout, an onboarding illustration)
- there is no cheap textual or semantic assertion that would catch the regression
- the component is stable; a screen still under design churn will produce a baseline update per PR

Delete one when it has been re-baselined twice without anyone reading the diff. At that point it is costing review time and catching nothing.

Do **not** put goldens on whole screens full of live data, on anything with a repeating animation (the baseline captures an arbitrary frame), or on a screen whose content includes a timestamp — pin the clock first, see `async-and-time.md`.

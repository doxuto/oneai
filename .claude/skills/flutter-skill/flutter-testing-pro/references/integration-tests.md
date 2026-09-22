# Integration tests

Read this when a test must run on a real device or emulator, when a flow spans more than one screen and real plugins, or when frame timings are being measured. Integration tests are the slowest and least reliable tests in the pyramid, so the guiding question is always "could a widget test have caught this?"

## Setup

```yaml
# pubspec.yaml
dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
```

Or `flutter pub add "dev:integration_test:{sdk: flutter}"`.

`integration_test` ships with the SDK; it has no pub version of its own and must not be pinned to a `^x.y.z` constraint.

```dart
// integration_test/app_test.dart
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:my_app/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('end-to-end', () {
    testWidgets('a signed-out user can sign in and reach the home screen',
        (tester) async {
      app.main();
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const ValueKey('email')), 'a@example.com');
      await tester.enterText(find.byKey(const ValueKey('password')), 'hunter2');
      await tester.tap(find.byKey(const ValueKey('sign-in')));
      await tester.pumpAndSettle(const Duration(seconds: 5));

      expect(find.byKey(const ValueKey('home-scaffold')), findsOneWidget);
    });
  });
}
```

`IntegrationTestWidgetsFlutterBinding.ensureInitialized()` must be the first statement in `main()`. It installs `LiveTestWidgetsFlutterBinding`, so unlike a widget test the clock is **real**, plugins are **real**, and the network is **real**.

Consequences that trip people up:

- `pumpAndSettle()` waits in real time and can legitimately take seconds. Pass an explicit `duration`/`timeout` for slow screens.
- There is no fake `HttpOverrides`; requests go out. Point the app at a staging environment or the Firebase emulators.
- `tester.pump(const Duration(seconds: 1))` does not skip a second; it waits one.
- Timer-leak assertions do not fire, so a leaked timer that a widget test would have caught passes here.

## Running

```bash
# Device or emulator (one must be attached)
flutter test integration_test/app_test.dart
flutter test integration_test                 # the whole directory
flutter test integration_test -d <device-id>
```

`--concurrency` is ignored for integration tests: they run one at a time against one device.

For web, screenshots, or a `flutter_driver`-style report, add a driver entry point:

```dart
// test_driver/integration_test.dart
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
```

```bash
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/app_test.dart \
  -d chrome

# Headless
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/app_test.dart \
  -d web-server
```

```dart
Future<void> integrationDriver({
  Duration timeout = const Duration(minutes: 20),
  ResponseDataCallback? responseDataCallback = writeResponseData,
  bool writeResponseOnFailure = false,
})
```

`responseDataCallback` receives whatever the test put in `binding.reportData` and, by default (`writeResponseData`), writes it to `build/integration_response_data.json`.

On Firebase Test Lab and other device farms, the Android path is the Gradle `assembleAndroidTest` / `assembleDebug -Ptarget=...` pair and the iOS path is an Xcode test bundle; both are documented in the `integration_test` package README rather than here.

## Screenshots

Screenshots require the driver, and Android requires converting the surface first.

```dart
// integration_test/screenshot_test.dart
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('captures the home screen', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    if (Platform.isAndroid) {
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
    }
    await binding.takeScreenshot('home');
  });
}
```

```dart
// test_driver/integration_test.dart
import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await integrationDriver(
    onScreenshot: (String name, List<int> bytes, [Map<String, Object?>? args]) async {
      await File('screenshots/$name.png').writeAsBytes(bytes);
      return true;
    },
  );
}
```

`Future<List<int>> takeScreenshot(String screenshotName, [Map<String, Object?>? args])`. The `onScreenshot` callback lives on the *extended* driver (`integration_test_driver_extended.dart`), not on the plain `integrationDriver`. These are device screenshots, not goldens — they are artefacts for humans, and comparing them byte-for-byte across devices does not work.

## Performance traces

```dart
final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

testWidgets('scrolling the feed stays under budget', (tester) async {
  app.main();
  await tester.pumpAndSettle();

  await binding.watchPerformance(() async {
    final listFinder = find.byType(ListView);
    for (var i = 0; i < 5; i++) {
      await tester.fling(listFinder, const Offset(0, -400), 3000);
      await tester.pumpAndSettle();
    }
  }, reportKey: 'scroll_perf');
});
```

| Member | Signature | Produces |
|---|---|---|
| `watchPerformance` | `Future<void> watchPerformance(Future<void> Function() action, {String reportKey = 'performance'})` | a `FrameTiming` summary under `reportKey` |
| `traceAction` | `Future<void> traceAction(Future<dynamic> Function() action, {List<String> streams = const <String>['all'], bool retainPriorEvents = false, String reportKey = 'timeline'})` | a raw timeline, `flutter_driver` style |
| `reportData` | `Map<String, dynamic>? reportData` | the payload handed to `responseDataCallback` |

`traceAction` is the lower-level of the two and produces a large timeline; `watchPerformance` gives the summarised build/raster percentiles that a budget assertion actually needs. `flutter_test` also exports `FrameTimingSummarizer` for turning raw `FrameTiming` lists into percentiles.

Run performance tests in **profile** mode (`flutter drive --profile`). Numbers from a debug build measure the debug build.

Assert on percentiles with generous budgets, not on averages:

```dart
// in the driver, after the run
final summary = response.data!['scroll_perf'] as Map<String, dynamic>;
expect(summary['90th_percentile_frame_build_time_millis'], lessThan(16.0));
```

Exact key names vary with the summariser version — print the map once and read it rather than guessing.

## What belongs here versus in a widget test

| Concern | Where |
|---|---|
| Does the button show a spinner while saving? | widget test |
| Does the form validate an empty e-mail? | widget test |
| Does the error banner appear on a 500? | widget test with a fake client |
| Does the real keychain/biometric plugin work? | integration test |
| Does deep-linking from a cold start land on the right screen? | integration test |
| Does the purchase flow survive an app backgrounding? | integration test |
| Does sign-up → verify → onboarding → home complete? | integration test, one of them |
| Is the card 8px from the edge? | golden |
| Is the scroll smooth? | integration test with `watchPerformance`, profile mode |

If an integration test would pass with all the plugins faked, it should have been a widget test.

## Keeping them few and stable

1. **Budget a number.** Five to ten flows for a mature app. Every addition should replace something, not accumulate.
2. **One flow per test, with a fresh app start.** Tests that depend on the previous test's leftover state fail in a different order on a different machine.
3. **Reset backend state between runs.** Use the Firebase emulator suite with a seeded fixture and clear it in `setUp`, or a per-run test account. Shared long-lived accounts are the top cause of "it only fails on Tuesdays".
4. **Key every element the test touches.** `find.text('Continue')` breaks when a copywriter changes the label; `find.byKey(const ValueKey('cta-continue'))` does not. Keys are owned by `flutter-widgets-pro`.
5. **No `sleep`, no bare `Future.delayed`.** Wait for a condition: `pumpAndSettle` with a timeout, or a loop that pumps until a finder matches.
6. **Run them on a schedule and on merge to main, not on every PR.** A twelve-minute device job on every push trains the team to ignore red.
7. **Quarantine rather than retry.** A flow that fails intermittently gets moved to a separate, non-blocking job with an owner and a date, not a `retry: 3`.

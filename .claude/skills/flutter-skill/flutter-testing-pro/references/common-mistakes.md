# Common mistakes: removed, deprecated, and hallucinated test APIs

Read this before asserting that a testing API exists. Everything below was checked against api.flutter.dev (`flutter_test`, `integration_test`), docs.flutter.dev/release/breaking-changes, and pub.dev on 2026-09-22 for Flutter 3.47.5. The first table is APIs that no longer work; the second is names that are routinely emitted from memory and have never existed.

## Deprecated or removed

| Old | Replacement | Note |
|---|---|---|
| `tester.binding.window` (`TestWindow`) | `tester.view` (`TestFlutterView`) and `tester.platformDispatcher` (`TestPlatformDispatcher`) | Still present in 3.47.5, deprecated, scheduled for removal |
| `binding.window.physicalSizeTestValue` | `tester.view.physicalSize` | |
| `binding.window.devicePixelRatioTestValue` | `tester.view.devicePixelRatio` | |
| `binding.window.paddingTestValue` / `viewInsetsTestValue` | `tester.view.padding` / `tester.view.viewInsets` | |
| `binding.window.textScaleFactorTestValue` | `tester.platformDispatcher.textScaleFactorTestValue` | **Platform dispatcher, not view** — the single most common mis-port |
| `binding.window.localeTestValue` | `tester.platformDispatcher.localeTestValue` | |
| `binding.window.clearPhysicalSizeTestValue()` | `tester.view.resetPhysicalSize()` | |
| `binding.window.clearAllTestValues()` | `tester.view.reset()` for view values, `tester.platformDispatcher.clearAllTestValues()` for platform values | Two calls, not one |
| `channel.setMockMethodCallHandler(handler)` on a `MethodChannel` | `TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, handler)` | The instance method was removed |
| `MediaQueryData(textScaleFactor: 2.0)` | `MediaQueryData(textScaler: TextScaler.linear(2.0))` | `textScaleFactor` deprecated in 3.16 |
| `debugDefaultTargetPlatformOverride = TargetPlatform.iOS` in a test body | `testWidgets(..., variant: TargetPlatformVariant.only(TargetPlatform.iOS))` | The override leaks if the test throws |
| `flutter_driver` + `test_driver/app_test.dart` as the test suite | `integration_test` | See docs.flutter.dev/release/breaking-changes/flutter-driver-migration |
| `golden_toolkit`: `testGoldens`, `loadAppFonts`, `GoldenBuilder`, `multiScreenGolden`, `DeviceBuilder` | plain `testWidgets` + a `FontLoader` helper + explicit `tester.view.physicalSize` loops | Package discontinued at 0.15.0 (Feb 2023) |
| `Ahem` as the test font name | `FlutterTest` | Renamed; 1024 upem, 0.75em ascent, 0.25em descent |
| `mockito` `@GenerateMocks` for new code | `@GenerateNiceMocks` | The README names `@GenerateNiceMocks` as the recommended API |

## Never existed

| Hallucinated | Reality |
|---|---|
| `find.byText('x')` | `find.text('x')` |
| `find.byValueKey('x')` | `find.byKey(const ValueKey('x'))` — `byValueKey` is `flutter_driver`'s API |
| `find.byKeyValue(...)` | no such member |
| `tester.pumpAndSettleUntil(condition)` | no such method; loop `pump` and check a finder yourself |
| `tester.waitFor(finder)` | no such method; that is Appium/Patrol vocabulary |
| `tester.tapButton(...)`, `tester.typeText(...)` | `tester.tap`, `tester.enterText` |
| `tester.pumpUntilFound(finder)` | write the loop, or use `scrollUntilVisible` for scrollables |
| `findsOneWidget()` called as a function | `findsOneWidget` is a constant; `findsNWidgets(n)` is the function |
| `findsExactlyNWidgets(n)` | `findsNWidgets(n)`, or the generic `findsExactly(n)` |
| `expect(finder, matchesGoldenFile(...))` | `await expectLater(finder, matchesGoldenFile(...))` — it is an `AsyncMatcher` |
| `tester.binding.setSurfaceSize(Size)` returning void | it returns `Future<void>`; await it |
| `WidgetTester.pumpWidgetAndSettle(...)` | two calls: `pumpWidget` then `pumpAndSettle` |
| `TestWidgetsFlutterBinding.instance.window` as the modern API | deprecated; use `tester.view` |
| `integration_test: ^1.0.0` in `pubspec.yaml` | `integration_test: { sdk: flutter }` — it ships with the SDK and has no pub version |
| `IntegrationTestWidgetsFlutterBinding.ensureInitialized()` inside `setUp` | it belongs as the first statement of `main()` |
| `mocktail`'s `when(mock.f())` without a closure | `when(() => mock.f())` — mocktail always takes a closure; `mockito` never does |
| `verify(mock.f()).called(1)` in a mocktail file | `verify(() => mock.f()).called(1)` |
| `registerFallbackValue<T>()` with a type argument | `registerFallbackValue(someInstance)` takes a value |
| `FakeAsync().elapse(...)` with `await` inside the callback | the `fakeAsync` callback is synchronous; `await` there deadlocks the test |
| `emitsInOrder` requiring an import of `package:test` in a Flutter test | `flutter_test` re-exports the stream matchers |

## Structural mistakes that compile

### `pumpAndSettle`'s first argument is the frame interval, not a wait

```dart
// Wrong: this does not "wait up to 5 seconds". It pumps 5-second frames.
await tester.pumpAndSettle(const Duration(seconds: 5));

// Right: the timeout is the third positional parameter.
await tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 5),
);
```

`Future<int> pumpAndSettle([Duration duration = const Duration(milliseconds: 100), EnginePhase phase = EnginePhase.sendSemanticsUpdate, Duration timeout = const Duration(minutes: 10)])`.

### Asserting without pumping

```dart
// Before — the tap's setState has not produced a frame yet
await tester.tap(find.byType(ElevatedButton));
expect(find.text('Saved'), findsOneWidget);

// After
await tester.tap(find.byType(ElevatedButton));
await tester.pump();
expect(find.text('Saved'), findsOneWidget);
```

### A mutable fixture at `main()` scope

```dart
// Before — one instance for the whole file
void main() {
  final repository = FakeTodoRepository();
  test('a', () { repository.failNextWith = Exception(); ... });
  test('b', () { ... });   // still armed to fail
}

// After
void main() {
  late FakeTodoRepository repository;
  setUp(() => repository = FakeTodoRepository());
}
```

### A global set without a teardown

```dart
// Before — the next test in this file renders at 320x568
tester.view.physicalSize = const Size(320, 568);

// After
tester.view.physicalSize = const Size(320, 568);
addTearDown(tester.view.reset);
```

### A widget pumped without an app ancestor

```dart
// Before — "No Directionality widget found" / "No MediaQuery widget ancestor"
await tester.pumpWidget(const TodoCard(todo: todo));

// After
await tester.pumpWidget(const MaterialApp(home: Scaffold(body: TodoCard(todo: todo))));
```

### Mocking a navigator observer with mocktail and no fallback

```dart
// Before — throws "registerFallbackValue" at the first any<Route>() use
class MockObserver extends Mock implements NavigatorObserver {}

// After
class _FakeRoute extends Fake implements Route<dynamic> {}

setUpAll(() => registerFallbackValue(_FakeRoute()));
```

A hand-written `FakeNavigatorObserver extends Fake implements NavigatorObserver` that records `didPush` avoids the problem entirely — see `test-doubles.md`.

### `SharedPreferences` mocked before the binding exists

```dart
// Before — throws "Binding has not yet been initialized"
void main() {
  SharedPreferences.setMockInitialValues({});
  test('...', () { ... });
}

// After
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
}
```

`testWidgets` initialises the binding itself; a plain `test` that touches platform channels does not.

### `--update-goldens` in the verification job

```yaml
# Before — this job can never fail
- run: flutter test --update-goldens --tags golden

# After
- run: flutter test --tags golden
```

## Boundaries — do not solve these here

| Symptom | Owner |
|---|---|
| `ProviderContainer.test()`, `overrideWith`, `overrideWithBuild`, awaiting `.future`, `tester.container()` | `riverpod-pro` → `references/testing.md` |
| Which key a widget should carry, how a page is composed, why a layout overflows | `flutter-widgets-pro` |
| Sealed error hierarchies, pattern matching in assertions, `Result` types | `dart-pro` |
| Faking `FirebaseAuth`/Firestore, emulator wiring, callable error codes | `flutter-firebase-contract`, and `firebase-skill` for the server halves |

# Widget tests

Read this for anything inside a `testWidgets` body. Every signature below was checked against api.flutter.dev (`flutter_test`) on 2026-09-22 for Flutter 3.47.5. The two things that break most widget tests are calling the wrong `pump` variant and asserting on tree shape instead of on what is rendered.

## The shape of a widget test

```dart
testWidgets('description of the behaviour', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: MyPage()));
  await tester.pump();

  expect(find.text('Hello'), findsOneWidget);
});
```

`testWidgets` installs `AutomatedTestWidgetsFlutterBinding`: a fake clock, a fake view, no real event loop, and a `WidgetTester`. Every `tester.*` method returns a `Future` and every one of them must be awaited. A missing `await` surfaces later as a `TestAsyncUtils` guard assertion, often in an unrelated test.

`pumpWidget` mounts a tree at the root. Calling it a second time in the same test replaces the root — useful for testing that a widget survives a parent rebuild, and a silent way to lose state if unintended.

Always pump a `MaterialApp` (or `WidgetsApp` / `CupertinoApp`) above anything that uses `Theme`, `Directionality`, `MediaQuery`, `Navigator` or `Localizations`. A bare `MyPage()` throws "No Directionality widget found"; wrapping it in `Directionality(textDirection: TextDirection.ltr, ...)` is a legitimate minimal alternative for a leaf widget.

## `pump`, `pump(duration)`, `pumpAndSettle`, `pumpFrames`

| Call | Signature | Behaviour |
|---|---|---|
| `pump()` | `Future<void> pump([Duration? duration, EnginePhase phase = EnginePhase.sendSemanticsUpdate])` | Flushes microtasks, then renders **one** frame |
| `pump(d)` | same | Advances the fake clock by `d`, then renders one frame |
| `pumpAndSettle()` | `Future<int> pumpAndSettle([Duration duration = const Duration(milliseconds: 100), EnginePhase phase = EnginePhase.sendSemanticsUpdate, Duration timeout = const Duration(minutes: 10)])` | Repeatedly pumps `duration`-sized frames until no frame is scheduled; returns the frame count; throws on `timeout` |
| `pumpFrames(target, maxDuration, [interval])` | `Future<void> pumpFrames(Widget target, Duration maxDuration, [Duration interval = const Duration(milliseconds: 16, microseconds: 683)])` | Pumps a fixed span of frames regardless of whether anything settles |

Decision procedure:

1. Does the interaction complete in one frame (a `setState`, an already-completed `Future`)? → `await tester.pump()`.
2. Is there a finite animation of known length (a 300 ms route transition, an `AnimatedContainer`)? → `await tester.pump()` to start it, then `await tester.pump(const Duration(milliseconds: 300))`.
3. Is there a chain of finite animations you do not want to enumerate? → `await tester.pumpAndSettle()`.
4. Is there *any* repeating animation on screen? → **never** `pumpAndSettle`. Use `pumpFrames` or a fixed number of `pump(const Duration(milliseconds: 16))`.

Things that never settle, and therefore hang `pumpAndSettle` until its ten-minute timeout:

- `CircularProgressIndicator` / `LinearProgressIndicator` with `value: null`
- any `AnimationController` with `repeat()`
- `Stream.periodic` driving a `StreamBuilder`
- a `Ticker` that is never disposed
- shimmer/skeleton packages
- a `Future` that only completes on real I/O (see `async-and-time.md` for `runAsync`)

`pumpAndSettle` returning `1` after a `tap` means nothing rebuilt — usually the tap missed. It does not fail; check the count or assert immediately after.

## Finders

`find` is the global `CommonFinders` instance.

| Finder | Signature | Use |
|---|---|---|
| `find.byKey(key)` | `byKey(Key key, {bool skipOffstage = true})` | The control a test drives. Best default. |
| `find.text(s)` | `text(String text, {bool findRichText = false, bool skipOffstage = true})` | Content the user reads. Set `findRichText: true` for `Text.rich`/`RichText`. |
| `find.textContaining(p)` | `textContaining(Pattern pattern, {bool findRichText = false, bool skipOffstage = true})` | Substring or `RegExp` match. |
| `find.byType(T)` | `byType(Type type, {bool skipOffstage = true})` | One-of-a-kind widgets only. |
| `find.widgetWithText(T, s)` | `widgetWithText(Type widgetType, String text, {bool skipOffstage = true})` | "the `ListTile` whose label is X" — the fix for ambiguous `byType`. |
| `find.widgetWithIcon(T, i)` | `widgetWithIcon(Type widgetType, IconData icon, {bool skipOffstage = true})` | Icon buttons. |
| `find.widgetWithImage(T, p)` | `widgetWithImage(Type widgetType, ImageProvider image, {bool skipOffstage = true})` | Avatars, thumbnails. |
| `find.descendant(...)` | `descendant({required FinderBase<Element> of, required FinderBase<Element> matching, bool matchRoot = false, bool skipOffstage = true})` | Scope a search to one subtree. |
| `find.ancestor(...)` | `ancestor({required FinderBase<Element> of, required FinderBase<Element> matching, bool matchRoot = false})` | Walk upward from a known leaf. |
| `find.byWidgetPredicate(p)` | `byWidgetPredicate(WidgetPredicate predicate, {String? description, bool skipOffstage = true})` | Match on a widget's properties. Always pass `description`. |
| `find.byElementPredicate(p)` | `byElementPredicate(ElementPredicate predicate, {String? description, bool skipOffstage = true})` | Rare; element-level matching. |
| `find.bySemanticsLabel(p)` | `bySemanticsLabel(Pattern label, {bool skipOffstage = true})` | Accessibility assertions. Requires `SemanticsHandle` in some setups. |
| `find.bySemanticsIdentifier(p)` | `bySemanticsIdentifier(Pattern identifier, {bool skipOffstage = true})` | Matches `SemanticsProperties.identifier`. |
| `find.byTooltip(p)` | `byTooltip(Pattern message, {bool skipOffstage = true})` | Toolbar actions. |
| `find.byIcon(i)` | `byIcon(IconData icon, {bool skipOffstage = true})` | `Icons.close` etc. |
| `find.byWidget(w)` | `byWidget(Widget widget, {bool skipOffstage = true})` | A widget instance you already hold. |
| `find.backButton()` / `find.closeButton()` | — | Platform-correct back/close affordances. |

Narrowing helpers on any finder: `.first`, `.last`, `.at(i)`, `.hitTestable()`. `skipOffstage: false` reaches widgets inside an inactive `Offstage`, an unselected `IndexedStack`, or an off-screen `TabBarView` page.

```dart
// Before — two FloatingActionButtons on the page, ambiguous
await tester.tap(find.byType(FloatingActionButton));

// After
await tester.tap(find.byKey(const ValueKey('add-todo')));

// Or, scoped
await tester.tap(find.descendant(
  of: find.byKey(const ValueKey('todo-1')),
  matching: find.byIcon(Icons.delete),
));
```

## Matchers

| Matcher | Kind | Matches |
|---|---|---|
| `findsOneWidget` | constant | exactly one widget |
| `findsNothing` | constant | no candidates |
| `findsWidgets` | constant | one or more widgets |
| `findsNWidgets(n)` | function | exactly `n` widgets |
| `findsAtLeastNWidgets(n)` | function | `n` or more widgets |
| `findsOne` | constant | exactly one candidate (any `FinderBase`) |
| `findsAny` | constant | one or more candidates (any `FinderBase`) |
| `findsExactly(n)` | function | exactly `n` candidates (any `FinderBase`) |
| `findsAtLeast(n)` | function | `n` or more candidates (any `FinderBase`) |

The `*Widget(s)` family is widget-specific; `findsOne`/`findsAny`/`findsExactly`/`findsAtLeast` are the generic versions that also work with semantics finders. None of the eight is deprecated in 3.47.5 — `findsAtLeast` did not replace `findsAtLeastNWidgets`, they coexist.

Reading state out of the tree:

```dart
tester.widget<Checkbox>(find.byType(Checkbox)).value;   // typed widget instance
tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList();
tester.state<MyPageState>(find.byType(MyPage)).someField;
tester.element(find.byType(MyPage));
tester.getSize(find.byType(Card));
tester.getTopLeft(find.byType(Card));
tester.getRect(find.byType(Card));
tester.getSemantics(find.byType(MyPage));
```

`expect(tester.takeException(), isNull)` at the end of a layout-sensitive test is how you assert "no overflow, no exception". `takeException()` consumes the most recent framework exception; a test that expects one asserts `isA<FlutterError>()` instead.

## Interacting

| Call | Signature (abridged) | Notes |
|---|---|---|
| `tap` | `tap(FinderBase<Element> finder, {int? pointer, int buttons = kPrimaryButton, bool warnIfMissed = true})` | `warnIfMissed` prints when the hit test lands on a different widget |
| `tapAt` | `tapAt(Offset location, {...})` | For coordinates rather than widgets |
| `longPress` | `longPress(FinderBase<Element> finder, {...})` | Sends down, waits `kLongPressTimeout`, sends up |
| `enterText` | `enterText(FinderBase<Element> finder, String text)` | Focuses the field and replaces its contents |
| `drag` | `drag(FinderBase<Element> finder, Offset offset, {double touchSlopX = kDragSlopDefault, double touchSlopY = kDragSlopDefault, bool warnIfMissed = true, ...})` | Moves by `offset` with no inertia |
| `fling` | `fling(FinderBase<Element> finder, Offset offset, double speed, {Duration frameInterval = const Duration(milliseconds: 16), ...})` | Adds velocity; needs `pumpAndSettle` or explicit pumps afterwards |
| `scrollUntilVisible` | `scrollUntilVisible(FinderBase<Element> finder, double delta, {FinderBase<Element>? scrollable, int maxScrolls = 50, Duration duration = const Duration(milliseconds: 50)})` | The correct way to reach an item in a long `ListView.builder` |
| `dragUntilVisible` | `dragUntilVisible(FinderBase<Element> finder, FinderBase<Element> view, Offset moveStep, {int maxIteration = 50, ...})` | When the scrollable is not the obvious one |
| `ensureVisible` | `ensureVisible(FinderBase<Element> finder)` | Scrolls a *built* but off-screen widget into view |
| `pageBack` | `pageBack()` | Taps the platform back affordance |
| `showKeyboard` | `showKeyboard(FinderBase<Element> finder)` | Focus without typing |
| `sendKeyEvent` | `sendKeyEvent(LogicalKeyboardKey key)` | Hardware keys, shortcuts |

A lazily-built `ListView` has not created off-screen children, so `ensureVisible` fails on them — `scrollUntilVisible` is the one that works:

```dart
await tester.scrollUntilVisible(
  find.text('Item 400'),
  300,                                     // pixels per scroll step
  scrollable: find.byType(Scrollable).first,
);
```

After `enterText`, pump before asserting; the field's `onChanged` and any listeners run in the following frame.

## View, text scale, and surface size

`tester.view` is a `TestFlutterView`; `tester.platformDispatcher` is a `TestPlatformDispatcher`.

| Property | Owner | Reset |
|---|---|---|
| `physicalSize` | `tester.view` | `resetPhysicalSize()` or `reset()` |
| `devicePixelRatio` | `tester.view` | `resetDevicePixelRatio()` or `reset()` |
| `padding`, `viewInsets`, `displayFeatures` | `tester.view` | `reset()` |
| `textScaleFactorTestValue` | `tester.platformDispatcher` | `clearTextScaleFactorTestValue()` or `clearAllTestValues()` |
| `platformBrightnessTestValue` | `tester.platformDispatcher` | `clearPlatformBrightnessTestValue()` |
| `localeTestValue` / `localesTestValue` | `tester.platformDispatcher` | `clearLocaleTestValue()` / `clearLocalesTestValue()` |
| `accessibilityFeaturesTestValue` | `tester.platformDispatcher` | `clearAccessibilityFeaturesTestValue()` |

```dart
testWidgets('fits a small phone at 2x text', (tester) async {
  tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 2.0;
  tester.platformDispatcher.textScaleFactorTestValue = 2.0;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);

  await tester.pumpWidget(const MyApp());
  await tester.pump();

  expect(tester.takeException(), isNull);
});
```

`physicalSize` is in physical pixels, so divide by `devicePixelRatio` to reason in logical pixels. `tester.binding.setSurfaceSize(Size? size)` sets the **logical** size of `tester.view` instead, and `setSurfaceSize(null)` restores the default — it is the shorter path when you do not care about the pixel ratio.

These values live on the binding, not the test, so they persist into the next test in the file. Every one of them needs an `addTearDown`.

`tester.binding.window` (`TestWindow`) still exists but is deprecated and will be removed. Any `binding.window.physicalSizeTestValue` or `binding.window.textScaleFactorTestValue` in a diff should be migrated to the table above.

## Pumping an infinite animation

```dart
testWidgets('shimmer paints without throwing', (tester) async {
  await tester.pumpWidget(const MaterialApp(home: LoadingSkeleton()));

  // Never pumpAndSettle here. Advance a bounded number of frames instead.
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }

  expect(tester.takeException(), isNull);
});
```

`await tester.pumpFrames(const MaterialApp(home: LoadingSkeleton()), const Duration(seconds: 1))` does the same thing in one call and is the idiomatic form when the target widget is the whole tree.

## Goldens from a widget test

```dart
await expectLater(
  find.byType(TodoCard),
  matchesGoldenFile('goldens/todo_card.png'),
);
```

`matchesGoldenFile(Object key, {int? version})` returns an `AsyncMatcher`, so it needs `expectLater` and `await`. The `Finder` form renders the nearest enclosing `RepaintBoundary`; wrap the subject in `RepaintBoundary` when you want the crop to be exactly that widget. Full detail, including why the baseline differs on your machine, is in `golden-tests.md`.

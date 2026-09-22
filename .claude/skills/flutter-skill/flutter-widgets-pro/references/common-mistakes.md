# Common mistakes: removed, renamed, and hallucinated widget APIs

Read this before asserting that a widget-layer API exists. Everything below was checked against api.flutter.dev, docs.flutter.dev/release/breaking-changes, or pub.dev on 2026-09-22 for Flutter 3.47.5. The first two tables are the APIs most often emitted from memory; the rest are structural bugs that compile but misbehave.

## Removed — these no longer exist

| Removed | Replacement | Removed in |
|---|---|---|
| `RaisedButton` | `ElevatedButton` | 3.0 (deprecated after 2.10) |
| `FlatButton` | `TextButton` | 3.0 |
| `OutlineButton` | `OutlinedButton` | 3.0 |
| `RaisedButtonTheme` / `FlatButtonTheme` / `ButtonTheme` for the above | `ElevatedButtonTheme` / `TextButtonTheme` / `OutlinedButtonTheme` | 3.0 |
| `Scaffold.of(context).showSnackBar` | `ScaffoldMessenger.of(context).showSnackBar` | 3.0 |
| `Scaffold.of(context).hideCurrentSnackBar` / `removeCurrentSnackBar` | `ScaffoldMessenger.of(context).…` | 3.0 |
| `TextField.maxLengthEnforced` | `maxLengthEnforcement` (`MaxLengthEnforcement`) | 3.0 |
| `Stack.overflow` | `Stack.clipBehavior` | 3.0 |
| `ThemeData.accentColor`, `accentColorBrightness`, `accentTextTheme`, `accentIconTheme`, `buttonColor` | `colorScheme.secondary` and the component themes | 3.10 (removed after 3.7) |
| `AppBar.brightness` | `AppBar.systemOverlayStyle` | 3.10 |
| `AppBar.textTheme` | `toolbarTextStyle` / `titleTextStyle` | 3.10 |
| `AppBarTheme.color` | `AppBarTheme.backgroundColor` | 3.10 |
| `AnimatedSize.vsync` | Remove the argument | 3.10 |
| `TextButton.styleFrom(primary:, onSurface:)` and the `ElevatedButton`/`OutlinedButton` equivalents | `foregroundColor:`, `backgroundColor:`, `disabledForegroundColor:` | 3.19 |
| `NavigatorState.focusScopeNode` | `Navigator.of(context).focusNode.enclosingScope!` | 3.19 |
| `PlatformMenuBar.body` | `PlatformMenuBar.child` | 3.19 |
| `describeEnum(value)` | `value.name` | 3.47 |
| `TextTheme.headline1…headline6`, `subtitle1`, `subtitle2`, `bodyText1`, `bodyText2`, `caption`, `button`, `overline` | the M3 names (`material3-theming.md`) | 3.x |

## Deprecated — still compile, but wrong in new code

| Deprecated | Replacement | Since |
|---|---|---|
| `WillPopScope` | `PopScope` (predictive back does not work with `WillPopScope`) | 3.12 |
| `PopScope.onPopInvoked` | `onPopInvokedWithResult(bool didPop, T? result)` | 3.22 |
| `MediaQuery.of(context).textScaleFactor`, `MediaQuery.textScaleFactorOf` | `MediaQuery.textScalerOf(context)` → `TextScaler` | 3.16 |
| `Color.withOpacity(x)` | `Color.withValues(alpha: x)` — avoids precision loss | 3.27 |
| `ColorScheme.background` / `onBackground` | `surface` / `onSurface` | 3.18 |
| `ColorScheme.surfaceVariant` | `surfaceContainerHighest` | 3.18 |
| `ButtonBar` | `OverflowBar` | 3.24 |
| `ReorderableListView.onReorder` (and `ReorderableList`, `SliverReorderableList`) | `onReorderItem` — applies the `newIndex -= 1` correction itself | 3.41 |
| `ListView.separated` / `SliverList.separated` `findChildIndexCallback` | `findItemIndexCallback` — item indices, no `* 2` | 3.41 |
| `cacheExtent`, `cacheExtentStyle` on scrollables and viewports | `scrollCacheExtent: ScrollCacheExtent.pixels(n)` / `.viewport(f)` | 3.41 |
| `Radio.groupValue` / `Radio.onChanged` | A `RadioGroup` ancestor | 3.32 |
| `Semantics(header: true)` | `Semantics(headingLevel: 1)` — `header` is a no-op on iOS/Android | 3.47 |
| `OverlayPortal.targetsRootOverlay` | see the 3.38 breaking-change note | 3.38 |
| `containsSemantics` matcher | `isSemantics` | 3.41 |
| `TextInputConnection.setStyle` | — | 3.44 |
| `package:flutter/material.dart`, `package:flutter/cupertino.dart` | `package:material_ui/material_ui.dart`, `package:cupertino_ui/cupertino_ui.dart`; frozen in 3.44, decoupled in 3.47 | 3.47 |

`ThemeData.useMaterial3` is not deprecated yet but is documented as temporary and defaults to `true`; `useMaterial3: false` in new code is a finding.

## Moved

| Symbol | From | To |
|---|---|---|
| `CupertinoPageTransitionsBuilder` | Material library | Cupertino library (3.44) |
| `GlobalMaterialLocalizations` / `GlobalCupertinoLocalizations` | `package:flutter_localizations` | `package:material_ui` / `package:cupertino_ui`, and `GlobalMaterialLocalizations.delegates` now returns the full list |
| `MaterialState`, `MaterialStateProperty`, `MaterialStatesController` | Material library | `WidgetState`, `WidgetStateProperty`, `WidgetStatesController` in the widgets library |
| `ThemeData.cardTheme`'s type | `CardTheme` | `CardThemeData` |

## Real, but often assumed absent

- `Flex.spacing` (and therefore `Row(spacing:)` / `Column(spacing:)`) exists and defaults to `0.0`; it inserts space between adjacent children only. Prefer it over interleaved `SizedBox`es.
- `SliverList.separated`, `SliverMainAxisGroup`, `SliverCrossAxisGroup`, `SliverVariedExtentList` all exist.
- `MediaQuery.withClampedTextScaling(minScaleFactor:, maxScaleFactor:, child:)` exists and is the supported way to bound text scaling for one subtree.

## Frequently hallucinated — these do not exist

- `Widget.rebuild()`, `context.rebuild()`, `setState()` outside a `State`.
- `BuildContext.size` — use a `GlobalKey` and `renderBox.size` after layout.
- `MediaQuery.widthOf` is real; `MediaQuery.screenWidth`, `context.screenWidth`, `Get.width` are not (the last is GetX).
- `ListView.builder(itemCount: ..., builder: ...)` — the parameter is `itemBuilder`.
- `Text('x', style: TextStyle(...))` with `fontWeight: 600` — `FontWeight.w600`, not an int.
- `Navigator.pushNamedAndRemoveUntilRoute`, `Navigator.clearStack` — the real API is `pushNamedAndRemoveUntil(context, name, predicate)`.
- `GoRouter.of(context).currentLocation` — read `GoRouterState.of(context).uri` or `matchedLocation`.
- `context.goNamed` exists; `context.navigate`, `context.pushRoute` do not.
- `ThemeData.colorScheme.primaryVariant` / `secondaryVariant` — removed long ago; use `primaryContainer` / `secondaryContainer`.
- `Theme.of(context).accentColor`, `.errorColor`, `.backgroundColor` — colour lives on `colorScheme`.
- `SafeArea(sliver: ...)` — the sliver form is `SliverSafeArea`.
- `Expanded` inside a `Stack`, `Positioned` inside a `Column` — both throw `Incorrect use of ParentDataWidget`.
- `FutureBuilder(future: someFuture())` built inline — see the structural list below.

## Structural bugs that compile

**Controller created in `build`.** A new `TextEditingController`/`AnimationController`/`ScrollController` every frame: input is lost and instances leak. Create in `initState`, dispose in `dispose`.

**`Future` or `Stream` created in `build` and passed to `FutureBuilder`/`StreamBuilder`.** A new future every rebuild restarts the work and flashes the loading state.

```dart
// Before
FutureBuilder<User>(future: api.fetchUser(id), builder: ...)

// After — the future is created once
late final Future<User> _user = api.fetchUser(widget.id);
FutureBuilder<User>(future: _user, builder: ...)
```

Better still, hand it to a provider: `riverpod-pro`.

**`setState` after `dispose`.** Any `await` inside a `State` needs `if (!mounted) return;` before touching `setState` or `context` (`state-lifecycle.md`).

**`context` used after an async gap.** Capture `ScaffoldMessenger.of(context)`, `Navigator.of(context)`, `GoRouter.of(context)` *before* the await. This is `use_build_context_synchronously`.

**`ListView` directly inside a `Column`.** Throws "Vertical viewport was given unbounded height". Use `Expanded`; `shrinkWrap: true` compiles but disables recycling.

**`ListView(children: items.map(...).toList())` for a data-driven list.** Builds everything eagerly. Use `.builder`.

**No keys on reorderable/removable list items.** `State` migrates between rows on removal — checkboxes and text fields appear to jump.

**A `GlobalKey` per list item, or a `GlobalKey`/`UniqueKey` allocated in `build`.** Global keys force unmount/remount on move; a fresh `UniqueKey` every build destroys the subtree every frame.

**A `Widget _buildX()` helper instead of a widget class.** No `const`, no separate element, rebuilds with the parent (`widget-fundamentals.md`).

**Hardcoded `Colors.*` or literal `TextStyle` in a widget.** Breaks dark mode and theming (`material3-theming.md`).

**`MediaQuery.of(context)` when only the size is wanted.** Rebuilds on keyboard, brightness, and text-scale changes.

**`Opacity(opacity: 0)` to hide a subtree.** Still builds, lays out, and forces a save-layer. Use `Visibility` or do not build it.

**Nested `Scaffold`s for a tabbed UI.** Two `ScaffoldMessenger` scopes and duplicated `AppBar` behaviour. Use one `Scaffold` and a `StatefulShellRoute` (`navigation.md`).

**`Navigator` used for something that must be deep-linkable.** Push-based navigation has no URL and no restoration.

**`InkWell` with no `Material` ancestor, or with an opaque widget between it and the `Material`.** No ripple. Since 3.44 `ListTile` reports this as a debug error; the fix is `Material(type: MaterialType.transparency)` or moving the colour onto the `Material`.

**A fixed-height `SizedBox` around text.** Overflows at large text scales (`accessibility.md`).

**`WidgetsBindingObserver` added but never removed.** Keeps the whole `State` alive for the process lifetime.

## Verification habit

Before asserting a widget parameter, constructor, or enum value: check `api.flutter.dev/flutter/<library>/<Class>-class.html` for the current signature and the "deprecated" annotations, and `docs.flutter.dev/release/breaking-changes` for the migration note. For packages, check the pub.dev changelog for the major version in `pubspec.yaml` — `go_router` in particular has had breaking changes in 15, 16, 17, and 18. If a name cannot be confirmed, write the code without it rather than guessing a plausible spelling.

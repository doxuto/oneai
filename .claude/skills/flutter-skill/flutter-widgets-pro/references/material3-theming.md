# Material 3 theming

Read this whenever a colour, a `TextStyle`, or a component style appears in widget code. The test is simple: a widget that names a literal colour or builds a `TextStyle` from scratch is unthemed, and it will be wrong in dark mode, wrong at high contrast, and wrong when the brand colour changes.

## Flutter 3.47: Material lives in a package

Material and Cupertino were decoupled from the SDK in Flutter 3.47.

```dart
// Before
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

// After
import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
```

- Migrate with `dart fix --apply --code=migrate_design_widgets`, and add the packages with `flutter pub add material_ui cupertino_ui`.
- `package:flutter/widgets.dart`, `rendering.dart`, `services.dart`, `foundation.dart`, `gestures.dart`, `animation.dart`, `painting.dart`, `scheduler.dart`, `semantics.dart` are unchanged and still in the SDK.
- The in-framework design libraries were frozen in 3.44 and are scheduled for formal deprecation and removal. They still compile in 3.47.
- The symbol names are identical, but the *types* differ between the two libraries. A package that migrated (go_router 18 depends on `material_ui ^1.0.0`) will not accept a `FloatingActionButtonLocation` or `ThemeData` from `package:flutter/material.dart`. Mixing the two is the source of confusing "argument type X is not the type X" errors where both sides print the same class name.
- `MaterialUiCompatibilityBridge` bridges theme and localisation state into subtrees whose dependencies still use the old imports. It cannot fix type mismatches in API signatures.
- Localisation delegates moved with the packages: `localizationsDelegates: GlobalMaterialLocalizations.delegates` replaces the hand-listed `GlobalMaterialLocalizations.delegate` / `GlobalCupertinoLocalizations.delegate` / `GlobalWidgetsLocalizations.delegate` from `flutter_localizations`.

## `ThemeData` shape

```dart
ThemeData _theme(Brightness brightness) {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF3A5AFE),
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    contrastLevel: 0.0,
  );
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    visualDensity: VisualDensity.adaptivePlatformDensity,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
      ),
    ),
    extensions: const <ThemeExtension<dynamic>>[AppSpacing.standard],
  );
}
```

- `useMaterial3` defaults to `true` and is documented as temporary; do not set it, and treat `useMaterial3: false` in new code as a finding.
- Pass `colorScheme:`, not `primarySwatch:` / `primaryColor:`. A swatch is a Material 2 concept and only approximates the M3 roles.
- Build the light and dark themes from the same seed with different `brightness`, and give `MaterialApp` both `theme:` and `darkTheme:` plus `themeMode: ThemeMode.system`.
- `ColorScheme.fromSeed` parameters: `seedColor` (required), `brightness`, `dynamicSchemeVariant`, `contrastLevel`, plus per-role overrides. `DynamicSchemeVariant` values include `tonalSpot` (the default, matches the M3 spec), `fidelity`, `content`, `monochrome`, `neutral`, `vibrant`, `expressive`, `rainbow`, `fruitSalad`.
- For Android dynamic colour, wrap with `DynamicColorBuilder` from `package:dynamic_color` and fall back to `fromSeed` when the platform scheme is null.

## Colour roles

Never write `Colors.blue`, `Colors.grey[300]`, or `Color(0xFF...)` inside a widget. Read a role.

| Role | Use for | Text/icons on it |
|---|---|---|
| `primary` | The main brand action: FAB, filled button | `onPrimary` |
| `primaryContainer` | A lower-emphasis primary surface | `onPrimaryContainer` |
| `secondary` / `secondaryContainer` | Less prominent accents, filter chips | `onSecondary` / `onSecondaryContainer` |
| `tertiary` / `tertiaryContainer` | Contrasting accent, balance | `onTertiary` / `onTertiaryContainer` |
| `error` / `errorContainer` | Validation, destructive | `onError` / `onErrorContainer` |
| `surface` | Page background, cards, sheets | `onSurface` |
| `surfaceDim`, `surfaceBright` | Extremes of the surface range | `onSurface` |
| `surfaceContainerLowest` … `surfaceContainerHighest` | The five elevation-like surface tiers | `onSurface` |
| `onSurfaceVariant` | Secondary text, inactive icons | — |
| `outline` / `outlineVariant` | Borders / dividers | — |
| `inverseSurface` / `onInverseSurface` / `inversePrimary` | Snackbars, inverted UI | — |
| `surfaceTint` | Elevation tint overlay | — |
| `shadow`, `scrim` | Shadows, modal barrier | — |
| `primaryFixed`, `primaryFixedDim`, `onPrimaryFixed`, `onPrimaryFixedVariant` (and secondary/tertiary equivalents) | Colours that stay the same in light and dark | — |

Deprecated roles and their replacements:

| Deprecated | Use |
|---|---|
| `background` | `surface` |
| `onBackground` | `onSurface` |
| `surfaceVariant` | `surfaceContainerHighest` |

M3 expresses elevation with a surface tint rather than a shadow: prefer moving between `surfaceContainer*` tiers over raising `elevation`.

## Typography

The M3 `TextTheme` is five roles × three sizes. The 2014/2018 names are gone.

| M3 | Old name |
|---|---|
| `displayLarge` / `displayMedium` / `displaySmall` | `headline1` / `headline2` / `headline3` |
| `headlineLarge` / `headlineMedium` / `headlineSmall` | `headline4` / `headline5` / — |
| `titleLarge` / `titleMedium` / `titleSmall` | `headline6` / `subtitle1` / `subtitle2` |
| `bodyLarge` / `bodyMedium` / `bodySmall` | `bodyText1` / `bodyText2` / `caption` |
| `labelLarge` / `labelMedium` / `labelSmall` | `button` / — / `overline` |

```dart
// Before
Text(title, style: Theme.of(context).textTheme.headline6)
Text(sub, style: const TextStyle(fontSize: 14, color: Colors.black54))

// After
final theme = Theme.of(context);
Text(title, style: theme.textTheme.titleLarge)
Text(sub, style: theme.textTheme.bodyMedium?.copyWith(
  color: theme.colorScheme.onSurfaceVariant,
))
```

Set a font once via `ThemeData(textTheme: GoogleFonts.interTextTheme(base.textTheme))` or `fontFamily:`, never per widget. Never set an absolute `fontSize` in a widget; `copyWith` a role instead so text scaling still applies.

## Component themes

Style a component once in `ThemeData` rather than at every call site. The `*ThemeData` classes take `WidgetStateProperty` values for state-dependent styling.

```dart
filledButtonTheme: FilledButtonThemeData(
  style: FilledButton.styleFrom(
    minimumSize: const Size(64, 48),
    shape: const StadiumBorder(),
  ),
),
inputDecorationTheme: InputDecorationTheme(
  filled: true,
  fillColor: scheme.surfaceContainerHighest,
  border: const OutlineInputBorder(),
),
navigationBarTheme: NavigationBarThemeData(
  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
),
segmentedButtonTheme: SegmentedButtonThemeData(
  style: ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith<Color?>(
      (Set<WidgetState> states) =>
          states.contains(WidgetState.selected) ? scheme.secondaryContainer : null,
    ),
  ),
),
```

The interactive-state API now lives in the widgets library as `WidgetState` (`hovered`, `focused`, `pressed`, `dragged`, `selected`, `scrolledUnder`, `disabled`, `error`) with `WidgetStateProperty`, `WidgetStatesController`, `WidgetStateColor`, `WidgetStateBorderSide`, `WidgetStateMouseCursor`. The `MaterialState*` names are the Material-specific aliases; prefer the `WidgetState*` spelling in new code.

M3 component names that replace M2 ones: `FilledButton` and `FilledButton.tonal` (new), `NavigationBar` (was `BottomNavigationBar`), `NavigationRail`, `NavigationDrawer` (was `Drawer` + `ListView`), `SearchBar`/`SearchAnchor`, `SegmentedButton` (was `ToggleButtons`), `Badge`, `CarouselView`. `ButtonBar` is deprecated in favour of `OverflowBar`.

## Dark mode

- Two `ThemeData`s from one seed; do not hand-build a dark palette.
- Check contrast at both brightnesses. `ColorScheme.fromSeed(contrastLevel: 0.5 /* or 1.0 */)` produces the M3 medium/high-contrast schemes; select on `MediaQuery.highContrastOf(context)`.
- `Theme.of(context).brightness` for a one-off branch; better still, use a role that already differs.
- Images and illustrations do not theme themselves — supply a dark variant or a `ColorFiltered` treatment.

## `ThemeExtension`

For design tokens the M3 scheme does not cover — spacing, brand gradients, semantic colours like "success":

```dart
import 'dart:ui' show lerpDouble;

@immutable
class AppSpacing extends ThemeExtension<AppSpacing> {
  const AppSpacing({required this.gutter, required this.section});

  static const AppSpacing standard = AppSpacing(gutter: 16, section: 32);

  final double gutter;
  final double section;

  @override
  AppSpacing copyWith({double? gutter, double? section}) =>
      AppSpacing(gutter: gutter ?? this.gutter, section: section ?? this.section);

  @override
  AppSpacing lerp(ThemeExtension<AppSpacing>? other, double t) {
    if (other is! AppSpacing) return this;
    return AppSpacing(
      gutter: lerpDouble(gutter, other.gutter, t)!,
      section: lerpDouble(section, other.section, t)!,
    );
  }
}

// Usage
final spacing = Theme.of(context).extension<AppSpacing>()!;
```

`extension<T>()` returns `null` when the extension is not registered — either assert at app start or provide a default. Both `copyWith` and `lerp` must be implemented or theme animation breaks.

## Adaptive and platform-aware

- `ThemeData.platform` drives which platform's look Material uses; override it in tests or for a forced look.
- `.adaptive` constructors pick a Cupertino-flavoured implementation on iOS/macOS: `Switch.adaptive`, `Slider.adaptive`, `CircularProgressIndicator.adaptive`, `Checkbox.adaptive`, `Radio.adaptive`, `AlertDialog.adaptive`, `showAdaptiveDialog`, `RefreshIndicator.adaptive`.
- `Theme.of(context).platform == TargetPlatform.iOS` for branching, not `Platform.isIOS` (which fails on web and ignores the theme override).
- `PageTransitionsTheme` sets per-platform route transitions. `CupertinoPageTransitionsBuilder` moved to the Cupertino library in 3.44 — import Cupertino to use it. The Android default became `PredictiveBackPageTransitionsBuilder` in 3.38.

## Density and shape

- `VisualDensity.adaptivePlatformDensity` gives compact controls on desktop and comfortable ones on touch. Setting a tighter density shrinks tap targets — check `accessibility.md` before doing it.
- Define corner radii once in the component themes (`cardTheme`, `dialogTheme`, `chipTheme`, `filledButtonTheme`), not at call sites. M3 shape scale: 4 / 8 / 12 / 16 / 28 logical pixels for extra-small through extra-large, with `StadiumBorder` for fully rounded.
- `Theme.of(context)` registers a dependency and rebuilds the widget on any theme change — that is correct and cheap. Do not "optimise" it by caching a `ThemeData` in a field.

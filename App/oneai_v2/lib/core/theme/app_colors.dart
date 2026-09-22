import 'package:flutter/material.dart';

/// Colour palette carried over verbatim from One AI v1.
///
/// Every value here is copied from `docs/07-APP-UI-FLOW-SPEC.md`, which is the
/// frozen design contract. Do not change a value without a task of its own.
abstract final class AppColors {
  // --- Light ---
  static const Color lightPrimary = Color(0xFF2C7DF7);
  static const Color lightOnPrimary = Color(0xFFFFFFFF);
  static const Color lightPrimaryContainer = Color(0xFFE8DDFF);
  static const Color lightOnPrimaryContainer = Color(0xFF21005E);
  static const Color lightSecondary = Color(0xFF03DAC6);
  static const Color lightOnSecondary = Color(0xFF000000);
  static const Color lightSecondaryContainer = Color(0xFFCEFAF8);
  static const Color lightOnSecondaryContainer = Color(0xFF002021);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightOnSurface = Color(0xFF1C1B1F);
  static const Color lightSurfaceContainerHighest = Color(0xFFE7E0EB);
  static const Color lightOnSurfaceVariant = Color(0xFF49454E);
  static const Color lightError = Color(0xFFB00020);
  static const Color lightOnError = Color(0xFFFFFFFF);
  static const Color lightOutline = Color(0xFFBDBDBD);
  static const Color lightShadow = Color(0xFF000000);
  static const Color lightInverseSurface = Color(0xFF313033);
  static const Color lightOnInverseSurface = Color(0xFFF4EFF4);
  static const Color lightInversePrimary = Color(0xFFCFBCFF);

  // --- Dark ---
  // Defined in v1 but never applied at runtime: main.dart passed
  // `theme: lightTheme` with no darkTheme/themeMode. Kept here so turning dark
  // mode on is a deliberate decision (OQ-08), not a rewrite.
  static const Color darkPrimary = Color(0xFFBB86FC);
  static const Color darkOnPrimary = Color(0xFF000000);
  static const Color darkPrimaryContainer = Color(0xFF4F378B);
  static const Color darkOnPrimaryContainer = Color(0xFFE8DDFF);
  static const Color darkSecondary = Color(0xFF03DAC6);
  static const Color darkOnSecondary = Color(0xFF000000);
  static const Color darkSecondaryContainer = Color(0xFF00504C);
  static const Color darkOnSecondaryContainer = Color(0xFFBBF5F1);
  static const Color darkSurface = Color(0xFF121212);
  static const Color darkOnSurface = Color(0xFFE6E1E5);
  static const Color darkSurfaceContainerHighest = Color(0xFF49454F);
  static const Color darkOnSurfaceVariant = Color(0xFFCAC4D0);
  static const Color darkError = Color(0xFFCF6679);
  static const Color darkOnError = Color(0xFF000000);
  static const Color darkOutline = Color(0xFF938F99);
  static const Color darkShadow = Color(0xFF000000);
  static const Color darkInverseSurface = Color(0xFFE6E1E5);
  static const Color darkOnInverseSurface = Color(0xFF1C1B1F);
  static const Color darkInversePrimary = Color(0xFF6750A4);

  /// Defined in v1's palette classes but never passed into the ColorScheme
  /// constructor, so Material's defaults applied instead. Kept as constants so
  /// nothing is lost, and deliberately NOT wired into the schemes below —
  /// wiring them would change how error surfaces render.
  static const Color lightErrorContainer = Color(0xFFFFDAD4);
  static const Color lightOnErrorContainer = Color(0xFF410001);
  static const Color darkErrorContainer = Color(0xFF8C0009);
  static const Color darkOnErrorContainer = Color(0xFFFFDAD4);
  static const Color scrim = Color(0xFF000000);

  /// Brand blues the v1 UI hardcoded instead of reading from the scheme.
  /// Named here so the rebuild references a token, and the values still match
  /// pixel for pixel. Consolidating them is a separate, reviewed task (S8-05).
  static const Color brandBlue = Color(0xFF0767F8);
  static const Color brandBlueAlt = Color(0xFF2C7DF7);
  static const Color brandBlueGoogle = Color(0xFF4285F4);
  static const Color destructiveRed = Color(0xFFE41919);
  static const Color dividerGrey = Color(0xFFBDBDBD);

  static const ColorScheme light = ColorScheme(
    brightness: Brightness.light,
    primary: lightPrimary,
    onPrimary: lightOnPrimary,
    primaryContainer: lightPrimaryContainer,
    onPrimaryContainer: lightOnPrimaryContainer,
    secondary: lightSecondary,
    onSecondary: lightOnSecondary,
    secondaryContainer: lightSecondaryContainer,
    onSecondaryContainer: lightOnSecondaryContainer,
    surface: lightSurface,
    onSurface: lightOnSurface,
    surfaceContainerHighest: lightSurfaceContainerHighest,
    onSurfaceVariant: lightOnSurfaceVariant,
    error: lightError,
    onError: lightOnError,
    outline: lightOutline,
    shadow: lightShadow,
    inverseSurface: lightInverseSurface,
    onInverseSurface: lightOnInverseSurface,
    inversePrimary: lightInversePrimary,
    surfaceTint: lightPrimary,
  );

  static const ColorScheme dark = ColorScheme(
    brightness: Brightness.dark,
    primary: darkPrimary,
    onPrimary: darkOnPrimary,
    primaryContainer: darkPrimaryContainer,
    onPrimaryContainer: darkOnPrimaryContainer,
    secondary: darkSecondary,
    onSecondary: darkOnSecondary,
    secondaryContainer: darkSecondaryContainer,
    onSecondaryContainer: darkOnSecondaryContainer,
    surface: darkSurface,
    onSurface: darkOnSurface,
    surfaceContainerHighest: darkSurfaceContainerHighest,
    onSurfaceVariant: darkOnSurfaceVariant,
    error: darkError,
    onError: darkOnError,
    outline: darkOutline,
    shadow: darkShadow,
    inverseSurface: darkInverseSurface,
    onInverseSurface: darkOnInverseSurface,
    inversePrimary: darkInversePrimary,
    surfaceTint: darkPrimary,
  );
}

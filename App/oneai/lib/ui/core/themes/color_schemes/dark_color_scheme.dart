import 'package:flutter/material.dart';

/// Color palette for dark theme
class DarkColorScheme {
  // Primary colors
  static const Color primary = Color(0xFFBB86FC);
  static const Color primaryContainer = Color(0xFF4F378B);
  static const Color onPrimaryContainer = Color(0xFFE8DDFF);

  // Secondary colors
  static const Color secondary = Color(0xFF03DAC6);
  static const Color secondaryContainer = Color(0xFF00504C);
  static const Color onSecondaryContainer = Color(0xFFBBF5F1);

  // Background colors
  static const Color background = Color(0xFF121212);
  static const Color onBackground = Color(0xFFE6E1E5);
  static const Color surface = Color(0xFF121212);
  static const Color onSurface = Color(0xFFE6E1E5);
  static const Color surfaceVariant = Color(0xFF49454F);
  static const Color onSurfaceVariant = Color(0xFFCAC4D0);

  // Error colors
  static const Color error = Color(0xFFCF6679);
  static const Color onError = Color(0xFF000000);
  static const Color errorContainer = Color(0xFF8C0009);
  static const Color onErrorContainer = Color(0xFFFFDAD4);

  // Neutral colors
  static const Color outline = Color(0xFF938F99);
  static const Color shadow = Color(0xFF000000);
  static const Color scrim = Color(0xFF000000);
}

/// Creates the color scheme for the dark theme
ColorScheme createDarkColorScheme() => const ColorScheme(
  primary: DarkColorScheme.primary,
  primaryContainer: DarkColorScheme.primaryContainer,
  onPrimaryContainer: DarkColorScheme.onPrimaryContainer,
  secondary: DarkColorScheme.secondary,
  secondaryContainer: DarkColorScheme.secondaryContainer,
  onSecondaryContainer: DarkColorScheme.onSecondaryContainer,
  surface: DarkColorScheme.surface,
  onSurface: DarkColorScheme.onSurface,
  error: DarkColorScheme.error,
  onError: DarkColorScheme.onError,
  onPrimary: Colors.black,
  onSecondary: Colors.black,
  surfaceContainerHighest: DarkColorScheme.surfaceVariant,
  onSurfaceVariant: DarkColorScheme.onSurfaceVariant,
  outline: DarkColorScheme.outline,
  shadow: DarkColorScheme.shadow,
  inverseSurface: Color(0xFFE6E1E5),
  onInverseSurface: Color(0xFF1C1B1F),
  inversePrimary: Color(0xFF6750A4),
  surfaceTint: DarkColorScheme.primary,
  brightness: Brightness.dark,
);

import 'package:flutter/material.dart';

/// Color palette for light theme
class LightColorScheme {
  // Primary colors
  static const Color primary = Color(0xFF2C7DF7);
  static const Color primaryContainer = Color(0xFFE8DDFF);
  static const Color onPrimaryContainer = Color(0xFF21005E);

  // Secondary colors
  static const Color secondary = Color(0xFF03DAC6);
  static const Color secondaryContainer = Color(0xFFCEFAF8);
  static const Color onSecondaryContainer = Color(0xFF002021);

  // Background colors
  static const Color background = Color(0xFFFFFFFF);
  static const Color onBackground = Color(0xFF1C1B1F);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF1C1B1F);
  static const Color surfaceVariant = Color(0xFFE7E0EB);
  static const Color onSurfaceVariant = Color(0xFF49454E);

  // Error colors
  static const Color error = Color(0xFFB00020);
  static const Color onError = Color(0xFFFFFFFF);
  static const Color errorContainer = Color(0xFFFFDAD4);
  static const Color onErrorContainer = Color(0xFF410001);

  // Neutral colors
  static const Color outline = Color(0xFFBDBDBD);
  static const Color shadow = Color(0xFF000000);
  static const Color scrim = Color(0xFF000000);
}

/// Creates the color scheme for the light theme
ColorScheme createLightColorScheme() => const ColorScheme(
  primary: LightColorScheme.primary,
  primaryContainer: LightColorScheme.primaryContainer,
  onPrimaryContainer: LightColorScheme.onPrimaryContainer,
  secondary: LightColorScheme.secondary,
  secondaryContainer: LightColorScheme.secondaryContainer,
  onSecondaryContainer: LightColorScheme.onSecondaryContainer,
  surface: LightColorScheme.surface,
  onSurface: LightColorScheme.onSurface,
  error: LightColorScheme.error,
  onError: LightColorScheme.onError,
  onPrimary: Colors.white,
  onSecondary: Colors.black,
  surfaceContainerHighest: LightColorScheme.surfaceVariant,
  onSurfaceVariant: LightColorScheme.onSurfaceVariant,
  outline: LightColorScheme.outline,
  shadow: LightColorScheme.shadow,
  inverseSurface: Color(0xFF313033),
  onInverseSurface: Color(0xFFF4EFF4),
  inversePrimary: Color(0xFFCFBCFF),
  surfaceTint: LightColorScheme.primary,
  brightness: Brightness.light,
);

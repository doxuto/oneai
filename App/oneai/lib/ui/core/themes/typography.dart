import 'package:flutter/material.dart';

/// Typography definitions for the application
class AppTypography {
  /// Creates consistent text theme for both light and dark modes
  static TextTheme createTextTheme() => const TextTheme(
    // Display styles
    displayLarge: TextStyle(fontSize: 57, fontWeight: FontWeight.w400, letterSpacing: -0.25),
    displayMedium: TextStyle(fontSize: 45, fontWeight: FontWeight.w400, letterSpacing: 0),
    displaySmall: TextStyle(fontSize: 36, fontWeight: FontWeight.w400, letterSpacing: 0),

    // Headline styles
    headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w400, letterSpacing: 0),
    headlineMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w400, letterSpacing: 0),
    headlineSmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w400, letterSpacing: 0),

    // Title styles
    titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, letterSpacing: 0),
    titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, letterSpacing: 0.15),
    titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1),

    // Label styles
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, letterSpacing: 0.1),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.5),
    labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.5),

    // Body styles
    bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, letterSpacing: 0.5),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: -0.41),
    bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 0.4),
  );

  /// Apply font family to text theme
  static TextTheme applyFontFamily(TextTheme textTheme, String? fontFamily) {
    if (fontFamily == null) {
      return textTheme;
    }

    return textTheme.apply(fontFamily: fontFamily);
  }
}

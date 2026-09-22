import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Helper class for theme-related utilities
class ThemeHelpers {
  /// Returns the brightness based on the selected theme or system settings
  static Brightness getBrightness(BuildContext context) => Theme.of(context).brightness;

  /// Returns true if the current theme is dark
  static bool isDarkMode(BuildContext context) => getBrightness(context) == Brightness.dark;

  /// Sets the status bar and navigation bar colors directly without requiring a BuildContext
  static void updateSystemUiOverlayDirect({
    required bool isDark,
    required ThemeData themeData,
    Color? statusBarColor,
    Color? navigationBarColor,
  }) {
    final colorScheme = themeData.colorScheme;

    SystemChrome.setSystemUIOverlayStyle(
      isDark
          ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: statusBarColor ?? Colors.transparent,
            systemNavigationBarColor: navigationBarColor ?? colorScheme.surface,
            systemNavigationBarIconBrightness: Brightness.light,
          )
          : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: statusBarColor ?? Colors.transparent,
            systemNavigationBarColor: navigationBarColor ?? colorScheme.surface,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
    );
  }

  /// Creates a color with transparency from a base color
  static Color withOpacity(Color color, double opacity) {
    assert(opacity >= 0 && opacity <= 1, 'Opacity must be between 0.0 and 1.0');
    final alpha = (opacity * 255).round();
    return color.withAlpha(alpha);
  }

  /// Creates a darker version of a color
  static Color darken(Color color, [double amount = 0.1]) {
    assert(amount >= 0 && amount <= 1, 'Amount must be between 0.0 and 1.0');
    final hsl = HSLColor.fromColor(color);
    final hslDark = hsl.withLightness((hsl.lightness - amount).clamp(0.0, 1.0));
    return hslDark.toColor();
  }

  /// Creates a lighter version of a color
  static Color lighten(Color color, [double amount = 0.1]) {
    assert(amount >= 0 && amount <= 1, 'Amount must be between 0.0 and 1.0');
    final hsl = HSLColor.fromColor(color);
    final hslLight = hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0));
    return hslLight.toColor();
  }

  /// Gets adaptive color based on brightness
  /// Returns lightColor in light mode and darkColor in dark mode
  static Color adaptiveColor(BuildContext context, Color lightColor, Color darkColor) =>
      isDarkMode(context) ? darkColor : lightColor;

  /// Returns a shade based on the primary color with a defined opacity
  static Color primaryShade(BuildContext context, {double opacity = 0.1}) {
    assert(opacity >= 0 && opacity <= 1, 'Opacity must be between 0.0 and 1.0');
    final primary = Theme.of(context).colorScheme.primary;
    final alpha = (opacity * 255).round();
    return primary.withAlpha(alpha);
  }
}

import 'package:flutter/material.dart';
import 'package:one_ai/core/theme/app_theme_extension.dart';

/// `context.colorScheme` / `context.textTheme` / `context.appTheme` — v1's
/// theme_helpers, kept so ported widgets read identically.
extension ThemeContext on BuildContext {
  ColorScheme get colorScheme => Theme.of(this).colorScheme;
  TextTheme get textTheme => Theme.of(this).textTheme;
  AppThemeExtension get appTheme => Theme.of(this).extension<AppThemeExtension>() ?? AppThemeExtension.light;
}

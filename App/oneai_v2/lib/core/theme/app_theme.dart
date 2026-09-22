import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/app_theme_extension.dart';
import 'package:one_ai/core/theme/app_typography.dart';

/// Component themes carried over verbatim from v1's light_theme/dark_theme.
abstract final class AppTheme {
  static ThemeData get light => _build(
        scheme: AppColors.light,
        extension: AppThemeExtension.light,
        overlayStyle: SystemUiOverlayStyle.dark,
      );

  static ThemeData get dark => _build(
        scheme: AppColors.dark,
        extension: AppThemeExtension.dark,
        overlayStyle: SystemUiOverlayStyle.light,
      );

  static ThemeData _build({
    required ColorScheme scheme,
    required AppThemeExtension extension,
    required SystemUiOverlayStyle overlayStyle,
  }) {
    final isDark = scheme.brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: AppTypography.fontFamily,
      textTheme: AppTypography.textTheme,
      extensions: <ThemeExtension<dynamic>>[extension],
      scaffoldBackgroundColor: scheme.surface,
      dividerColor: scheme.outline.withAlpha(51),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        systemOverlayStyle: overlayStyle.copyWith(statusBarColor: Colors.transparent),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        color: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(extension.cardRadius)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 2,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(extension.buttonRadius)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(extension.buttonRadius)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          side: BorderSide(color: scheme.outline),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(extension.buttonRadius)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(extension.buttonRadius),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(extension.buttonRadius),
          borderSide: BorderSide(color: scheme.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(extension.buttonRadius),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(extension.buttonRadius),
          borderSide: BorderSide(color: scheme.error),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surface,
        labelStyle: AppTypography.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(extension.buttonRadius)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(extension.dialogRadius)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        modalBackgroundColor: Colors.transparent,
        modalElevation: isDark ? 0 : null,
        constraints: const BoxConstraints.tightFor(width: double.infinity),
        shape: isDark
            ? RoundedRectangleBorder(borderRadius: BorderRadius.all(extension.dialogRadius))
            : null,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.primary : scheme.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.primary.withAlpha(128) : scheme.surface,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? scheme.primary : null,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.primary.withAlpha(77),
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withAlpha(31),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        circularTrackColor: scheme.primary.withAlpha(51),
        linearTrackColor: scheme.primary.withAlpha(51),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(color: scheme.onInverseSurface),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
      iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/core/theme/app_colors.dart';
import 'package:one_ai/core/theme/app_theme.dart';
import 'package:one_ai/core/theme/app_theme_extension.dart';
import 'package:one_ai/core/theme/app_typography.dart';

/// The design contract, enforced.
///
/// docs/07-APP-UI-FLOW-SPEC.md freezes these values. If one of these tests
/// fails, either a token drifted by accident, or the change is deliberate and
/// needs its own reviewed task — plus an update to that doc.
void main() {
  group('light ColorScheme matches v1 exactly', () {
    const s = AppColors.light;
    test('primary', () => expect(s.primary, const Color(0xFF2C7DF7)));
    test('onPrimary', () => expect(s.onPrimary, const Color(0xFFFFFFFF)));
    test('primaryContainer', () => expect(s.primaryContainer, const Color(0xFFE8DDFF)));
    test('onPrimaryContainer', () => expect(s.onPrimaryContainer, const Color(0xFF21005E)));
    test('secondary', () => expect(s.secondary, const Color(0xFF03DAC6)));
    test('secondaryContainer', () => expect(s.secondaryContainer, const Color(0xFFCEFAF8)));
    test('onSecondaryContainer', () => expect(s.onSecondaryContainer, const Color(0xFF002021)));
    test('surface', () => expect(s.surface, const Color(0xFFFFFFFF)));
    test('onSurface', () => expect(s.onSurface, const Color(0xFF1C1B1F)));
    test('surfaceContainerHighest',
        () => expect(s.surfaceContainerHighest, const Color(0xFFE7E0EB)));
    test('onSurfaceVariant', () => expect(s.onSurfaceVariant, const Color(0xFF49454E)));
    test('error', () => expect(s.error, const Color(0xFFB00020)));
    test('outline', () => expect(s.outline, const Color(0xFFBDBDBD)));
    test('inverseSurface', () => expect(s.inverseSurface, const Color(0xFF313033)));
    test('onInverseSurface', () => expect(s.onInverseSurface, const Color(0xFFF4EFF4)));
    test('inversePrimary', () => expect(s.inversePrimary, const Color(0xFFCFBCFF)));
    test('surfaceTint equals primary', () => expect(s.surfaceTint, s.primary));
  });

  group('dark ColorScheme matches v1 exactly', () {
    const s = AppColors.dark;
    test('primary', () => expect(s.primary, const Color(0xFFBB86FC)));
    test('surface', () => expect(s.surface, const Color(0xFF121212)));
    test('onSurface', () => expect(s.onSurface, const Color(0xFFE6E1E5)));
    test('error', () => expect(s.error, const Color(0xFFCF6679)));
    test('outline', () => expect(s.outline, const Color(0xFF938F99)));
    test('inversePrimary', () => expect(s.inversePrimary, const Color(0xFF6750A4)));
  });

  group('typography matches v1 exactly', () {
    const t = AppTypography.textTheme;
    test('displayLarge', () {
      expect(t.displayLarge?.fontSize, 57);
      expect(t.displayLarge?.letterSpacing, -0.25);
    });
    test('titleMedium', () {
      expect(t.titleMedium?.fontSize, 16);
      expect(t.titleMedium?.fontWeight, FontWeight.w500);
      expect(t.titleMedium?.letterSpacing, 0.15);
    });
    test('bodyMedium keeps the SF Pro letterSpacing', () {
      expect(t.bodyMedium?.fontSize, 14);
      expect(t.bodyMedium?.letterSpacing, -0.41);
    });
    test('no style sets height', () {
      for (final style in <TextStyle?>[
        t.displayLarge, t.displayMedium, t.displaySmall,
        t.headlineLarge, t.headlineMedium, t.headlineSmall,
        t.titleLarge, t.titleMedium, t.titleSmall,
        t.labelLarge, t.labelMedium, t.labelSmall,
        t.bodyLarge, t.bodyMedium, t.bodySmall,
      ]) {
        expect(style?.height, isNull);
      }
    });
  });

  group('AppThemeExtension matches v1 exactly', () {
    const e = AppThemeExtension.light;
    test('success', () => expect(e.successColor, const Color(0xFF00BFA5)));
    test('warning', () => expect(e.warningColor, const Color(0xFFFFC107)));
    test('radii', () {
      expect(e.buttonRadius, const Radius.circular(8));
      expect(e.cardRadius, const Radius.circular(12));
      expect(e.dialogRadius, const Radius.circular(16));
    });
    test('durations', () {
      expect(e.animationFast, const Duration(milliseconds: 200));
      expect(e.animationMedium, const Duration(milliseconds: 300));
      expect(e.animationSlow, const Duration(milliseconds: 500));
    });
    test('dark success/warning differ from light', () {
      expect(AppThemeExtension.dark.successColor, const Color(0xFF00C897));
      expect(AppThemeExtension.dark.warningColor, const Color(0xFFFFA000));
    });
  });

  group('component themes match v1', () {
    final light = AppTheme.light;
    test('material 3 is on', () => expect(light.useMaterial3, isTrue));
    test('appBar is flat and surface-coloured', () {
      expect(light.appBarTheme.elevation, 0);
      expect(light.appBarTheme.backgroundColor, AppColors.lightSurface);
    });
    test('card elevation 2', () => expect(light.cardTheme.elevation, 2));
    test('scaffold background is surface',
        () => expect(light.scaffoldBackgroundColor, AppColors.lightSurface));
    test('bottom sheet is transparent', () {
      expect(light.bottomSheetTheme.backgroundColor, Colors.transparent);
      expect(light.bottomSheetTheme.modalBackgroundColor, Colors.transparent);
    });
    test('the extension is attached',
        () => expect(light.extension<AppThemeExtension>(), isNotNull));
  });
}

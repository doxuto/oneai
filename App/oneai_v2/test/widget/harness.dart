import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/core/config/app_config.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/app_theme.dart';
import 'package:one_ai/bootstrap.dart';

/// Pumps one screen exactly as the app does — same theme, same l10n delegates —
/// with the given provider overrides. Tests never touch Firebase.
Future<void> pumpScreen(WidgetTester tester, Widget screen, {List<Override> overrides = const [], Locale locale = const Locale('en')}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(AppConfig.fromEnvironment()),
        ...overrides,
      ],
      child: MaterialApp(
        theme: AppTheme.light,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: screen,
      ),
    ),
  );
  await tester.pump();
}

/// The three guidelines every screen must pass (S9-03, a11y AA).
Future<void> expectAccessible(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
  handle.dispose();
}

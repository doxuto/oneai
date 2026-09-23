import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/data/models/user_models.dart';
import 'package:one_ai/features/ads/runtime/ad_hooks.dart';
import 'package:one_ai/features/billing/entitlement.dart';
import 'package:one_ai/features/credits/credits_provider.dart';
import 'package:one_ai/features/notifications/notification_prefs.dart';
import 'package:one_ai/features/settings/language_settings.dart';
import 'package:one_ai/features/settings/settings_screen.dart';

import 'harness.dart';

class _Prefs extends NotificationPrefsController {
  @override
  Future<NotificationPrefs> build() async => const NotificationPrefs(transcriptionDone: true);
}

List<Override> settingsOverrides({bool premium = false, bool privacyOptions = false}) => [
      authUserProvider.overrideWith((_) => Stream.value(null)),
      isPremiumProvider.overrideWith((_) => Stream.value(premium)),
      quotaProvider.overrideWith((_) => Stream.value(Quota(usedSeconds: 120, limitSeconds: 600, maxDurationSeconds: 600, resetAt: DateTime(2026, 9, 25)))),
      notificationPrefsProvider.overrideWith(() => _Prefs()),
      deviceLanguageCodeProvider.overrideWithValue('en'),
      privacyOptionsRequiredProvider.overrideWith((_) async => privacyOptions),
    ];

void main() {
  testWidgets('every v1 section is present and the screen is accessible', (tester) async {
    await pumpScreen(tester, const SettingsScreen(), overrides: settingsOverrides());
    await tester.pumpAndSettle();
    for (final label in ['Audio Language', 'Summary Language', 'Privacy policy', 'Terms of service', 'Sign out', 'Delete account']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Privacy options'), findsNothing, reason: 'hidden unless UMP requires it');
    await expectAccessible(tester);
  });

  testWidgets('Privacy options appears only when UMP requires it', (tester) async {
    await pumpScreen(tester, const SettingsScreen(), overrides: settingsOverrides(privacyOptions: true));
    await tester.pumpAndSettle();
    expect(find.text('Privacy options'), findsOneWidget);
  });

  testWidgets('notification toggle reflects the server preference', (tester) async {
    await pumpScreen(tester, const SettingsScreen(), overrides: settingsOverrides());
    await tester.pumpAndSettle();
    final sw = tester.widget<Switch>(find.byType(Switch).first);
    expect(sw.value, isTrue);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/config/remote_config.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/styled_dialog.dart';
import 'package:one_ai/features/billing/entitlement.dart';
import 'package:one_ai/features/billing/paywall.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lastShownKey = 'INTRO_BASIC_LAST_SHOWN_TIME'; // v1 key

/// v1's "Basic Plan Overview" popup for free users: text and frequency from
/// Remote Config, last-shown time per device. ATT is NOT requested here any
/// more — that moves after UMP consent (docs/08 §4, A6-02).
Future<void> maybeShowIntroBasicPopup(BuildContext context, WidgetRef ref) async {
  final premium = ref.read(isPremiumProvider).valueOrNull ?? false;
  if (premium) return;
  final rc = await ref.read(remoteConfigProvider.future);
  if (!rc.popupIntroBasicEnabled || rc.popupIntroBasicText.isEmpty) return;

  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    final last = DateTime.tryParse(prefs.getString(_lastShownKey) ?? '');
    if (last != null) {
      final freq = rc.popupIntroBasicFrequencyHours;
      if (freq == 0 || DateTime.now().difference(last).inHours < freq) return;
    }
  } on Object catch (_) {}

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => StyledDialog(
      title: ctx.l10n.basicPlanOverview,
      confirmLabel: ctx.l10n.goPremium,
      destructive: true,
      content: Text(rc.popupIntroBasicText, textAlign: TextAlign.center, style: ctx.textTheme.bodyMedium),
      onConfirm: () {
        Navigator.of(ctx).pop();
        ref.read(paywallProvider).present();
      },
    ),
  );
  try {
    await prefs?.setString(_lastShownKey, DateTime.now().toIso8601String());
  } on Object catch (_) {}
}

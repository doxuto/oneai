import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/theme/theme_context.dart';
import 'package:one_ai/core/widgets/styled_dialog.dart';
import 'package:one_ai/features/billing/paywall.dart';
import 'package:one_ai/features/credits/credit_gate.dart';
import 'package:one_ai/features/credits/credits_provider.dart';

/// v1's `premiumActionWrapper`, on the pure gate. Runs [action] when the
/// user has minutes for it; otherwise the "Premium Required" dialog (OQ-18)
/// and, on confirm, the paywall.
Future<void> runWithCreditGate(BuildContext context, WidgetRef ref, Future<void> Function() action, {int? requestedSeconds}) async {
  final outcome = creditGateDecide(status: ref.read(premiumStatusProvider), requestedSeconds: requestedSeconds, quota: ref.read(quotaProvider).valueOrNull);
  switch (outcome) {
    case CreditGateOutcome.proceed:
      await action();
    case CreditGateOutcome.offerUpgrade:
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => StyledDialog(
          title: ctx.l10n.premiumRequired,
          content: Text(ctx.l10n.noFreeMinutesLeft, textAlign: TextAlign.center, style: ctx.textTheme.bodyMedium),
          cancelLabel: ctx.l10n.cancel,
          confirmLabel: ctx.l10n.goPremium,
          onCancel: () => Navigator.of(ctx).pop(false),
          onConfirm: () => Navigator.of(ctx).pop(true),
        ),
      );
      if (go != true) return;
      final premium = await ref.read(paywallProvider).present();
      if (premium) await action();
  }
}

/// Button label: the normal text, or "Upgrade to continue" when out of minutes.
String creditGateLabel(BuildContext context, WidgetRef ref, String normal) =>
    ref.watch(premiumStatusProvider) == PremiumStatus.nonPremiumNoCredits ? context.l10n.upgradeToContinue : normal;

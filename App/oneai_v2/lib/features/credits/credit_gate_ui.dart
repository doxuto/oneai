import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/l10n/l10n.dart';
import 'package:one_ai/core/widgets/app_snack.dart';
import 'package:one_ai/features/ads/runtime/ad_hooks.dart';
import 'package:one_ai/features/billing/paywall.dart';
import 'package:one_ai/features/credits/credit_gate.dart';
import 'package:one_ai/features/credits/credits_provider.dart';

/// v1's `premiumActionWrapper`, on the pure gate. Runs [action] when the
/// user may transcribe; otherwise shows the loaded rewarded ad and waits for
/// the server to credit it, or offers the paywall. Never waits for an ad to
/// load (docs/08 §2).
Future<void> runWithCreditGate(BuildContext context, WidgetRef ref, Future<void> Function() action) async {
  final status = ref.read(premiumStatusProvider);
  final rewarded = ref.read(rewardedHookProvider);
  final outcome = creditGateDecide(
    status: status,
    // The hook's isReady already folds AdGate.rewarded + "is loaded".
    rewardedDecision: rewarded.isReady ? const AdAllowed() : const AdRefused(AdRefusal.formatDisabled),
    rewardedAdLoaded: rewarded.isReady,
  );
  switch (outcome) {
    case CreditGateOutcome.proceed:
      await action();
    case CreditGateOutcome.showRewardedAd:
      final before = ref.read(quotaProvider).valueOrNull?.rewardBonus ?? 0;
      final earned = await rewarded.show();
      if (!earned) {
        if (context.mounted) AppSnack.show(context, context.l10n.adNotCompleted);
        return;
      }
      if (context.mounted) AppSnack.show(context, context.l10n.rewardOnItsWay);
      final credited = await waitForRewardCredit(ref.read(quotaStreamProvider), rewardBonusBefore: before);
      if (!context.mounted) return;
      if (credited) {
        AppSnack.show(context, context.l10n.rewardReceived(1));
        await action();
      } else {
        AppSnack.show(context, context.l10n.somethingWentWrong);
      }
    case CreditGateOutcome.offerUpgrade:
      final premium = await ref.read(paywallProvider).present();
      if (premium) await action();
  }
}

/// Button label per v1: "Transcribe & Summarize" or "Watch Ad to Transcribe".
String creditGateLabel(BuildContext context, WidgetRef ref, String normal) =>
    ref.watch(premiumStatusProvider) == PremiumStatus.nonPremiumNoCredits ? context.l10n.watchAdToTranscribe : normal;

/// Same wait as inside the gate, for screens that show the ad themselves.
Future<bool> waitForRewardCreditWithRef(WidgetRef ref, int rewardBonusBefore) =>
    waitForRewardCredit(ref.read(quotaStreamProvider), rewardBonusBefore: rewardBonusBefore);

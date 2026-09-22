import 'dart:async';

import 'package:one_ai/data/models/user_models.dart';
import 'package:one_ai/features/ads/ad_gate.dart';

/// v1's `PremiumStatus` — same three values, same meaning.
enum PremiumStatus { premium, nonPremiumHasCredits, nonPremiumNoCredits }

PremiumStatus premiumStatusOf({required bool isPremium, required Quota? quota}) {
  if (isPremium) return PremiumStatus.premium;
  if (quota?.hasCredits ?? false) return PremiumStatus.nonPremiumHasCredits;
  return PremiumStatus.nonPremiumNoCredits;
}

/// What the record / upload button should do when tapped. Replaces v1's
/// `premiumActionWrapper`, minus the blocking "loading ad" dialog.
enum CreditGateOutcome {
  /// Premium, or a free user with credits left — run the action.
  proceed,

  /// No credits, and a rewarded ad is loaded and allowed — show it, then
  /// wait for the server-side reward (see [waitForRewardCredit]).
  showRewardedAd,

  /// No credits and no ad can be shown right now (not loaded, capped, ads
  /// disabled) — offer the paywall instead. Never block on an ad load.
  offerUpgrade,
}

CreditGateOutcome creditGateDecide({
  required PremiumStatus status,
  required AdDecision rewardedDecision,
  required bool rewardedAdLoaded,
}) {
  if (status != PremiumStatus.nonPremiumNoCredits) return CreditGateOutcome.proceed;
  if (rewardedDecision.isAllowed && rewardedAdLoaded) return CreditGateOutcome.showRewardedAd;
  return CreditGateOutcome.offerUpgrade;
}

/// After `onUserEarnedReward`, the credit arrives through AdMob → SSV →
/// Firestore, usually within a few seconds. Resolves true as soon as the
/// live quota shows a higher `rewardBonus` than before the ad (or credits
/// became available), false on [timeout]. The client never adds credit itself.
Future<bool> waitForRewardCredit(
  Stream<Quota?> quota, {
  required int rewardBonusBefore,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final done = Completer<bool>();
  late final StreamSubscription<Quota?> sub;
  sub = quota.listen(
    (q) {
      if (q == null) return;
      if (q.rewardBonus > rewardBonusBefore || q.hasCredits) {
        if (!done.isCompleted) done.complete(true);
      }
    },
    onError: (Object _) {
      if (!done.isCompleted) done.complete(false);
    },
    onDone: () {
      if (!done.isCompleted) done.complete(false);
    },
  );
  final timer = Timer(timeout, () {
    if (!done.isCompleted) done.complete(false);
  });
  try {
    return await done.future;
  } finally {
    timer.cancel();
    await sub.cancel();
  }
}

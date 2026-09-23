import 'package:one_ai/data/models/user_models.dart';

/// v1's `PremiumStatus` — same three values; "credits" now means minutes.
enum PremiumStatus { premium, nonPremiumHasCredits, nonPremiumNoCredits }

PremiumStatus premiumStatusOf({required bool isPremium, required Quota? quota}) {
  if (isPremium) return PremiumStatus.premium;
  if (quota?.canStart ?? false) return PremiumStatus.nonPremiumHasCredits;
  return PremiumStatus.nonPremiumNoCredits;
}

/// What the record / upload button does when tapped (decided 24/09: no
/// rewarded ads — out of minutes means the paywall, nothing else).
enum CreditGateOutcome { proceed, offerUpgrade }

CreditGateOutcome creditGateDecide({required PremiumStatus status, int? requestedSeconds, Quota? quota}) {
  if (status == PremiumStatus.premium) return CreditGateOutcome.proceed;
  if (status == PremiumStatus.nonPremiumNoCredits) return CreditGateOutcome.offerUpgrade;
  if (requestedSeconds != null && quota != null && !quota.canStartSeconds(requestedSeconds)) return CreditGateOutcome.offerUpgrade;
  return CreditGateOutcome.proceed;
}

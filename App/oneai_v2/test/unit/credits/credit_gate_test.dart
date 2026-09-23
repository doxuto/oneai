import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/data/models/user_models.dart';
import 'package:one_ai/features/credits/credit_gate.dart';

Quota q({int used = 0, int limit = 600, int maxDuration = 600}) =>
    Quota(usedSeconds: used, limitSeconds: limit, maxDurationSeconds: maxDuration, resetAt: DateTime(2026, 9, 25));

void main() {
  group('Quota (seconds per day, decided 24/09)', () {
    test('remaining, minutes, and the per-recording cap', () {
      final a = q(used: 130);
      expect(a.remainingSeconds, 470);
      expect(a.remainingMinutes, 7);
      expect(a.limitMinutes, 10);
      expect(a.maxRecordingSeconds, 470, reason: 'what is left today, under the 600 cap');
      expect(q(used: 0, maxDuration: 300).maxRecordingSeconds, 300);
    });
    test('canStart needs at least the one minute the server reserves', () {
      expect(q(used: 540).canStart, isTrue);
      expect(q(used: 541).canStart, isFalse);
      expect(q(used: 500).canStartSeconds(100), isTrue);
      expect(q(used: 500).canStartSeconds(101), isFalse);
      expect(q(used: 590).canStartSeconds(5), isFalse, reason: 'a 5-second clip still reserves 60');
    });
    test('limit 0 is unlimited', () {
      final p = q(used: 99999, limit: 0, maxDuration: 14400);
      expect(p.isUnlimited, isTrue);
      expect(p.canStart, isTrue);
      expect(p.maxRecordingSeconds, 14400);
    });
  });

  group('premiumStatusOf', () {
    test('premium wins; free depends on minutes left', () {
      expect(premiumStatusOf(isPremium: true, quota: q(used: 600)), PremiumStatus.premium);
      expect(premiumStatusOf(isPremium: false, quota: q(used: 0)), PremiumStatus.nonPremiumHasCredits);
      expect(premiumStatusOf(isPremium: false, quota: q(used: 600)), PremiumStatus.nonPremiumNoCredits);
      expect(premiumStatusOf(isPremium: false, quota: null), PremiumStatus.nonPremiumNoCredits);
    });
  });

  group('creditGateDecide (no rewarded ads)', () {
    test('premium always proceeds; out of minutes always offers upgrade', () {
      expect(creditGateDecide(status: PremiumStatus.premium), CreditGateOutcome.proceed);
      expect(creditGateDecide(status: PremiumStatus.nonPremiumNoCredits), CreditGateOutcome.offerUpgrade);
    });
    test('a free user with minutes proceeds only if the recording fits', () {
      expect(creditGateDecide(status: PremiumStatus.nonPremiumHasCredits), CreditGateOutcome.proceed);
      expect(creditGateDecide(status: PremiumStatus.nonPremiumHasCredits, requestedSeconds: 200, quota: q(used: 500)), CreditGateOutcome.offerUpgrade);
      expect(creditGateDecide(status: PremiumStatus.nonPremiumHasCredits, requestedSeconds: 90, quota: q(used: 500)), CreditGateOutcome.proceed);
    });
  });
}

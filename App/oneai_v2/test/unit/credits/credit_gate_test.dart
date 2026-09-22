import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/data/models/user_models.dart';
import 'package:one_ai/features/ads/ad_gate.dart';
import 'package:one_ai/features/credits/credit_gate.dart';

Quota q({int used = 0, int limit = 1, int bonus = 0}) =>
    Quota(used: used, limit: limit, rewardBonus: bonus, resetAt: DateTime(2026, 9, 24));

void main() {
  group('premiumStatusOf', () {
    test('premium wins regardless of quota', () {
      expect(premiumStatusOf(isPremium: true, quota: null), PremiumStatus.premium);
      expect(premiumStatusOf(isPremium: true, quota: q(used: 5, limit: 1)), PremiumStatus.premium);
    });
    test('free user with credits / without / unknown quota', () {
      expect(premiumStatusOf(isPremium: false, quota: q(used: 0, limit: 1)), PremiumStatus.nonPremiumHasCredits);
      expect(premiumStatusOf(isPremium: false, quota: q(used: 1, limit: 1)), PremiumStatus.nonPremiumNoCredits);
      expect(premiumStatusOf(isPremium: false, quota: null), PremiumStatus.nonPremiumNoCredits);
    });
    test('reward bonus is already folded into limit by the repository', () {
      expect(q(used: 1, limit: 2, bonus: 1).hasCredits, isTrue);
    });
  });

  group('creditGateDecide', () {
    test('proceeds for premium and for free-with-credits, ignoring the ad', () {
      for (final s in [PremiumStatus.premium, PremiumStatus.nonPremiumHasCredits]) {
        expect(
          creditGateDecide(status: s, rewardedDecision: const AdRefused(AdRefusal.masterSwitchOff), rewardedAdLoaded: false),
          CreditGateOutcome.proceed,
        );
      }
    });
    test('no credits + ad allowed + loaded → show the ad', () {
      expect(
        creditGateDecide(status: PremiumStatus.nonPremiumNoCredits, rewardedDecision: const AdAllowed(), rewardedAdLoaded: true),
        CreditGateOutcome.showRewardedAd,
      );
    });
    test('no credits + ad not loaded → upgrade, never wait for a load', () {
      expect(
        creditGateDecide(status: PremiumStatus.nonPremiumNoCredits, rewardedDecision: const AdAllowed(), rewardedAdLoaded: false),
        CreditGateOutcome.offerUpgrade,
      );
    });
    test('no credits + gate refused (cap, off) → upgrade', () {
      expect(
        creditGateDecide(status: PremiumStatus.nonPremiumNoCredits, rewardedDecision: const AdRefused(AdRefusal.dailyCap), rewardedAdLoaded: true),
        CreditGateOutcome.offerUpgrade,
      );
    });
  });

  group('waitForRewardCredit', () {
    test('resolves true when rewardBonus rises', () async {
      final ctl = StreamController<Quota?>();
      final f = waitForRewardCredit(ctl.stream, rewardBonusBefore: 0, timeout: const Duration(seconds: 5));
      ctl.add(q(used: 1, limit: 1, bonus: 0)); // unchanged
      ctl.add(q(used: 1, limit: 2, bonus: 1)); // SSV landed
      expect(await f, isTrue);
      expect(ctl.hasListener, isFalse, reason: 'subscription released');
      await ctl.close();
    });

    test('resolves true when credits appear for any reason (e.g. day rollover)', () async {
      final ctl = StreamController<Quota?>();
      final f = waitForRewardCredit(ctl.stream, rewardBonusBefore: 2, timeout: const Duration(seconds: 5));
      ctl.add(q(used: 0, limit: 1, bonus: 0));
      expect(await f, isTrue);
      await ctl.close();
    });

    test('ignores nulls and times out false', () async {
      final ctl = StreamController<Quota?>();
      final f = waitForRewardCredit(ctl.stream, rewardBonusBefore: 0, timeout: const Duration(milliseconds: 30));
      ctl.add(null);
      ctl.add(q(used: 1, limit: 1));
      expect(await f, isFalse);
      expect(ctl.hasListener, isFalse);
      await ctl.close();
    });

    test('stream error or close → false', () async {
      final a = StreamController<Quota?>();
      final fa = waitForRewardCredit(a.stream, rewardBonusBefore: 0);
      a.addError(Exception('perm'));
      expect(await fa, isFalse);
      await a.close();

      final b = StreamController<Quota?>();
      final fb = waitForRewardCredit(b.stream, rewardBonusBefore: 0);
      await b.close();
      expect(await fb, isFalse);
    });
  });
}

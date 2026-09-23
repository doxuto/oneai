import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/features/ads/ad_gate.dart';
import 'package:one_ai/features/ads/ad_ledger.dart';
import 'package:one_ai/features/ads/ads_config.dart';

// A fixed clock. Local-time day keys are used, so keep everything mid-day.
final t0 = DateTime(2026, 9, 23, 12, 0, 0);
DateTime at(int seconds) => t0.add(Duration(seconds: seconds));

const on = AdsConfig(enabled: true);

AdLedger warmedUp() => AdLedger()
  ..sessionCount = 4
  ..sessionStartedAt = at(-600)
  ..lifetimeCompletions = 10
  ..completionsSinceInterstitial = 5;

AdContext ctx(AdLedger l, {DateTime? now, bool entitled = true}) =>
    AdContext(ledger: l, adsEntitled: entitled, now: now ?? t0);

AdRefusal? reasonOf(AdDecision d) => switch (d) { AdAllowed() => null, AdRefused(:final reason) => reason };

void main() {
  group('common', () {
    test('master switch off wins over everything', () {
      expect(reasonOf(AdGate.rewarded(const AdsConfig(), ctx(warmedUp()))), AdRefusal.masterSwitchOff);
      expect(reasonOf(AdGate.interstitial(const AdsConfig(), ctx(warmedUp()))), AdRefusal.masterSwitchOff);
      expect(reasonOf(AdGate.appOpen(const AdsConfig(), ctx(warmedUp()), secondsInBackground: 999)), AdRefusal.masterSwitchOff);
    });
    test('premium (not entitled) never sees an ad', () {
      expect(reasonOf(AdGate.rewarded(on, ctx(warmedUp(), entitled: false))), AdRefusal.notEntitledToAds);
      expect(reasonOf(AdGate.banner(on, placement: 'summaryTab', adsEntitled: false)), AdRefusal.notEntitledToAds);
    });
    test('a config that fails to parse means ads OFF', () {
      expect(AdsConfig.parse('{not json').enabled, isFalse);
      expect(AdsConfig.parse(null).enabled, isFalse);
      expect(AdsConfig.parse('{"enabled":true,"interstitial":"garbage"}').interstitial.maxPerDay, 8); // domain default kept
    });
  });

  group('appOpen', () {
    test('first three sessions never show (strictly greater)', () {
      final l = warmedUp()..sessionCount = 3;
      expect(reasonOf(AdGate.appOpen(on, ctx(l), secondsInBackground: 60)), AdRefusal.earlySession);
      l.sessionCount = 4;
      expect(AdGate.appOpen(on, ctx(l), secondsInBackground: 60).isAllowed, isTrue);
    });
    test('background too short', () {
      expect(reasonOf(AdGate.appOpen(on, ctx(warmedUp()), secondsInBackground: 44)), AdRefusal.backgroundTooShort);
      expect(AdGate.appOpen(on, ctx(warmedUp()), secondsInBackground: 45).isAllowed, isTrue);
    });
    test('global cooldown after any full-screen dismissal', () {
      final l = warmedUp()..lastFullScreenDismissedAt = at(-10);
      expect(reasonOf(AdGate.appOpen(on, ctx(l), secondsInBackground: 60)), AdRefusal.fullScreenCooldown);
    });
    test('spacing since the same format', () {
      final l = warmedUp()..lastShownAt[AdFormat.appOpen] = at(-299);
      expect(reasonOf(AdGate.appOpen(on, ctx(l), secondsInBackground: 60)), AdRefusal.tooSoonSinceSameFormat);
    });
    test('daily cap', () {
      final l = warmedUp()
        ..dayKey = AdLedger.dayKeyOf(t0)
        ..shownToday[AdFormat.appOpen] = 4;
      expect(reasonOf(AdGate.appOpen(on, ctx(l), secondsInBackground: 60)), AdRefusal.dailyCap);
    });
    test('format disabled', () {
      const c = AdsConfig(enabled: true, appOpen: AppOpenRules(enabled: false));
      expect(reasonOf(AdGate.appOpen(c, ctx(warmedUp()), secondsInBackground: 60)), AdRefusal.formatDisabled);
    });
  });

  group('interstitial', () {
    test('needs lifetime completions first', () {
      final l = warmedUp()..lifetimeCompletions = 2;
      expect(reasonOf(AdGate.interstitial(on, ctx(l))), AdRefusal.tooFewLifetimeCompletions);
    });
    test('the first ever interstitial is not blocked by completions-between', () {
      final l = warmedUp()..completionsSinceInterstitial = 0;
      expect(AdGate.interstitial(on, ctx(l)).isAllowed, isTrue);
    });
    test('after one was shown, at least 2 completions are required — the floor is hard-coded', () {
      const lax = AdsConfig(enabled: true, interstitial: InterstitialRules(minimumCompletionsBetween: 0));
      final l = warmedUp()
        ..lastShownAt[AdFormat.interstitial] = at(-3600)
        ..completionsSinceInterstitial = 1;
      expect(reasonOf(AdGate.interstitial(lax, ctx(l))), AdRefusal.tooFewCompletionsSinceLast);
      l.completionsSinceInterstitial = 2;
      expect(AdGate.interstitial(lax, ctx(l)).isAllowed, isTrue);
    });
    test('session too young', () {
      final l = warmedUp()..sessionStartedAt = at(-10);
      expect(reasonOf(AdGate.interstitial(on, ctx(l))), AdRefusal.sessionTooYoung);
      final none = warmedUp()..sessionStartedAt = null;
      expect(reasonOf(AdGate.interstitial(on, ctx(none))), AdRefusal.sessionTooYoung);
    });
    test('placement must be enabled when given', () {
      expect(reasonOf(AdGate.interstitial(on, ctx(warmedUp()), placement: 'nope')), AdRefusal.placementDisabled);
      expect(AdGate.interstitial(on, ctx(warmedUp()), placement: 'summaryExit').isAllowed, isTrue);
    });
    test('order: cooldown before spacing before cap', () {
      final l = warmedUp()
        ..lastFullScreenDismissedAt = at(-5)
        ..lastShownAt[AdFormat.interstitial] = at(-5)
        ..dayKey = AdLedger.dayKeyOf(t0)
        ..shownToday[AdFormat.interstitial] = 99;
      expect(reasonOf(AdGate.interstitial(on, ctx(l))), AdRefusal.fullScreenCooldown);
      l.lastFullScreenDismissedAt = at(-3600);
      expect(reasonOf(AdGate.interstitial(on, ctx(l))), AdRefusal.tooSoonSinceSameFormat);
      l.lastShownAt[AdFormat.interstitial] = at(-3600);
      expect(reasonOf(AdGate.interstitial(on, ctx(l))), AdRefusal.dailyCap);
    });
  });

  group('rewarded — the short chain', () {
    test('off by default since 24/09; when enabled by RC it ignores cooldown, spacing and session — only the cap', () {
      expect(reasonOf(AdGate.rewarded(on, ctx(warmedUp()))), AdRefusal.formatDisabled);
      const on = AdsConfig(enabled: true, rewarded: RewardedRules(enabled: true, maxPerDay: 5));
      final l = warmedUp()
        ..lastFullScreenDismissedAt = at(-1)
        ..lastShownAt[AdFormat.rewarded] = at(-1)
        ..sessionStartedAt = null
        ..lifetimeCompletions = 0;
      expect(AdGate.rewarded(on, ctx(l)).isAllowed, isTrue);
      l
        ..dayKey = AdLedger.dayKeyOf(t0)
        ..shownToday[AdFormat.rewarded] = 5;
      expect(reasonOf(AdGate.rewarded(on, ctx(l))), AdRefusal.dailyCap);
    });
  });

  group('banner / native', () {
    test('placement gating', () {
      expect(AdGate.banner(on, placement: 'summaryTab', adsEntitled: true).isAllowed, isTrue);
      expect(reasonOf(AdGate.banner(on, placement: 'home', adsEntitled: true)), AdRefusal.placementDisabled);
      expect(reasonOf(AdGate.native(on, placement: 'minutesList', adsEntitled: true)), AdRefusal.formatDisabled); // native default off
    });
    test('nativeRows with defaults on a 40-item list', () {
      const c = NativeRules(enabled: true);
      expect(AdGate.nativeRows(40, c), [5, 15, 25]);
    });
    test('short lists get no ad and an ad never ends a list', () {
      const c = NativeRules(enabled: true);
      expect(AdGate.nativeRows(5, c), isEmpty);
      expect(AdGate.nativeRows(6, c), [5]);
    });
    test('nativeChunks agrees with nativeRows', () {
      const c = NativeRules(enabled: true, firstRow: 3, everyRows: 3, maxPerScreen: 2);
      final items = List.generate(10, (i) => i);
      expect(AdGate.nativeRows(10, c), [2, 5]);
      expect(AdGate.nativeChunks(items, c), [
        [0, 1],
        [2, 3, 4],
        [5, 6, 7, 8, 9],
      ]);
    });
  });

  group('ledger', () {
    test('recordShown on interstitial resets completionsSinceInterstitial', () {
      final l = warmedUp()..recordShown(AdFormat.interstitial, t0);
      expect(l.completionsSinceInterstitial, 0);
      expect(l.shownToday[AdFormat.interstitial], 1);
      expect(l.lastShownAt[AdFormat.interstitial], t0);
    });
    test('day rollover empties shownToday', () {
      final l = warmedUp()..recordShown(AdFormat.appOpen, t0);
      expect(l.shownTodayFor(AdFormat.appOpen, t0.add(const Duration(days: 1))), 0);
    });
    test('round-trips through JSON', () {
      final l = warmedUp()
        ..recordShown(AdFormat.rewarded, t0)
        ..recordFullScreenDismissed(at(5));
      final back = AdLedger.decode(l.encode());
      expect(back.sessionCount, 4);
      expect(back.lastShownAt[AdFormat.rewarded], t0);
      expect(back.lastFullScreenDismissedAt, at(5));
      expect(back.shownToday[AdFormat.rewarded], 1);
      expect(back.dayKey, AdLedger.dayKeyOf(t0));
    });
    test('garbage in storage yields a fresh ledger, never a crash', () {
      expect(AdLedger.decode('{{').sessionCount, 0);
      expect(AdLedger.decode(null).sessionCount, 0);
    });
  });
}

// PURE. No SDK, no DateTime.now(), no storage. Time and history are passed
// in, which is what makes every refusal testable. Port of
// ios-admob-ads-skill/templates/AdsCore/AdGate.swift — same order, same names.
import 'dart:math' as math;

import 'package:one_ai/features/ads/ad_ledger.dart';
import 'package:one_ai/features/ads/ads_config.dart';

enum AdRefusal {
  masterSwitchOff,
  notEntitledToAds,
  formatDisabled,
  placementDisabled,
  dailyCap,
  tooSoonSinceSameFormat,
  fullScreenCooldown,
  tooFewCompletionsSinceLast,
  tooFewLifetimeCompletions,
  sessionTooYoung,
  earlySession,
  backgroundTooShort,
}

sealed class AdDecision {
  const AdDecision();
  bool get isAllowed => this is AdAllowed;
}

final class AdAllowed extends AdDecision {
  const AdAllowed();
}

final class AdRefused extends AdDecision {
  const AdRefused(this.reason);
  final AdRefusal reason;
}

class AdContext {
  const AdContext({required this.ledger, required this.adsEntitled, required this.now});
  final AdLedger ledger;
  /// true = this user SHOULD see ads (i.e. not premium).
  final bool adsEntitled;
  final DateTime now;
}

abstract final class AdGate {
  /// The AdMob policy floor for interstitials, hard-coded on purpose — config
  /// may raise it, never lower it.
  static const int interstitialCompletionsFloor = 2;

  static AdRefusal? _common(AdsConfig c, AdContext ctx) {
    if (!c.enabled) return AdRefusal.masterSwitchOff;
    if (!ctx.adsEntitled) return AdRefusal.notEntitledToAds;
    return null;
  }

  static AdRefusal? _fullScreenCooldown(AdsConfig c, AdContext ctx) {
    final last = ctx.ledger.lastFullScreenDismissedAt;
    if (last != null && ctx.now.difference(last).inSeconds < c.fullScreenCooldownSeconds) {
      return AdRefusal.fullScreenCooldown;
    }
    return null;
  }

  static AdRefusal? _spacing(AdFormat f, int minSeconds, AdContext ctx) {
    final last = ctx.ledger.lastShownAt[f];
    if (last != null && ctx.now.difference(last).inSeconds < minSeconds) return AdRefusal.tooSoonSinceSameFormat;
    return null;
  }

  static AdRefusal? _cap(AdFormat f, int maxPerDay, AdContext ctx) {
    if (ctx.ledger.shownTodayFor(f, ctx.now) >= maxPerDay) return AdRefusal.dailyCap;
    return null;
  }

  static AdDecision appOpen(AdsConfig c, AdContext ctx, {required int secondsInBackground}) {
    final r = c.appOpen;
    final common = _common(c, ctx);
    if (common != null) return AdRefused(common);
    if (!r.enabled) return const AdRefused(AdRefusal.formatDisabled);
    // Strictly greater: with skipFirstSessions = 3 the 4th session is the first eligible.
    if (!(ctx.ledger.sessionCount > r.skipFirstSessions)) return const AdRefused(AdRefusal.earlySession);
    if (secondsInBackground < r.minimumBackgroundSeconds) return const AdRefused(AdRefusal.backgroundTooShort);
    final cd = _fullScreenCooldown(c, ctx);
    if (cd != null) return AdRefused(cd);
    final sp = _spacing(AdFormat.appOpen, r.minimumSecondsBetween, ctx);
    if (sp != null) return AdRefused(sp);
    final cap = _cap(AdFormat.appOpen, r.maxPerDay, ctx);
    if (cap != null) return AdRefused(cap);
    return const AdAllowed();
  }

  /// Call from a "done" moment AFTER ledger.recordCompletion().
  static AdDecision interstitial(AdsConfig c, AdContext ctx, {String? placement}) {
    final r = c.interstitial;
    final common = _common(c, ctx);
    if (common != null) return AdRefused(common);
    if (!r.enabled) return const AdRefused(AdRefusal.formatDisabled);
    if (placement != null && !r.placements.contains(placement)) return const AdRefused(AdRefusal.placementDisabled);
    if (ctx.ledger.lifetimeCompletions < r.minimumLifetimeCompletions) return const AdRefused(AdRefusal.tooFewLifetimeCompletions);
    final between = math.max(interstitialCompletionsFloor, r.minimumCompletionsBetween);
    if (ctx.ledger.lastShownAt[AdFormat.interstitial] != null && ctx.ledger.completionsSinceInterstitial < between) {
      return const AdRefused(AdRefusal.tooFewCompletionsSinceLast);
    }
    final started = ctx.ledger.sessionStartedAt;
    if (started == null || ctx.now.difference(started).inSeconds < r.minimumSessionSeconds) {
      return const AdRefused(AdRefusal.sessionTooYoung);
    }
    final cd = _fullScreenCooldown(c, ctx);
    if (cd != null) return AdRefused(cd);
    final sp = _spacing(AdFormat.interstitial, r.minimumSecondsBetween, ctx);
    if (sp != null) return AdRefused(sp);
    final cap = _cap(AdFormat.interstitial, r.maxPerDay, ctx);
    if (cap != null) return AdRefused(cap);
    return const AdAllowed();
  }

  /// User-initiated, so deliberately the shortest chain: no cooldown, no
  /// spacing, no session rules.
  static AdDecision rewarded(AdsConfig c, AdContext ctx) {
    final common = _common(c, ctx);
    if (common != null) return AdRefused(common);
    if (!c.rewarded.enabled) return const AdRefused(AdRefusal.formatDisabled);
    final cap = _cap(AdFormat.rewarded, c.rewarded.maxPerDay, ctx);
    if (cap != null) return AdRefused(cap);
    return const AdAllowed();
  }

  static AdDecision banner(AdsConfig c, {required String placement, required bool adsEntitled}) {
    if (!c.enabled) return const AdRefused(AdRefusal.masterSwitchOff);
    if (!adsEntitled) return const AdRefused(AdRefusal.notEntitledToAds);
    if (!c.banner.enabled) return const AdRefused(AdRefusal.formatDisabled);
    if (!c.banner.placements.contains(placement)) return const AdRefused(AdRefusal.placementDisabled);
    return const AdAllowed();
  }

  static AdDecision native(AdsConfig c, {required String placement, required bool adsEntitled}) {
    if (!c.enabled) return const AdRefused(AdRefusal.masterSwitchOff);
    if (!adsEntitled) return const AdRefused(AdRefusal.notEntitledToAds);
    if (!c.native.enabled) return const AdRefused(AdRefusal.formatDisabled);
    if (!c.native.placements.contains(placement)) return const AdRefused(AdRefusal.placementDisabled);
    return const AdAllowed();
  }

  /// Item indices BEFORE which a native ad is inserted. An ad is only placed
  /// with at least one content item after it, so short lists get none and an
  /// ad never ends a list.
  static List<int> nativeRows(int itemCount, NativeRules c) {
    final first = math.max(1, c.firstRow) - 1;
    final every = math.max(1, c.everyRows);
    if (c.maxPerScreen <= 0 || first < 0) return const [];
    final rows = <int>[];
    var index = first;
    while (index < itemCount && rows.length < c.maxPerScreen) {
      rows.add(index);
      index += every;
    }
    return rows;
  }

  /// Chunks of content between ads, DERIVED from nativeRows so list and grid
  /// can never disagree about where the third ad goes.
  static List<List<T>> nativeChunks<T>(List<T> items, NativeRules c) {
    final rows = nativeRows(items.length, c);
    if (rows.isEmpty) return [items];
    final out = <List<T>>[];
    var start = 0;
    for (final r in rows) {
      out.add(items.sublist(start, r));
      start = r;
    }
    out.add(items.sublist(start));
    return out;
  }
}

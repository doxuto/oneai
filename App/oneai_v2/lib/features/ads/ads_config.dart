// Mirrors Backend/oneai_backend/remote-config/ads_config.defaults.json.
// One Remote Config JSON parameter; a domain that fails to parse keeps its
// own defaults. Defaults are the SAFE side: ads off, wide spacing, low caps.
import 'dart:convert';

import 'package:one_ai/data/firebase/json_read.dart';

enum AdFormat { appOpen, interstitial, rewarded, banner, native }

class AppOpenRules {
  const AppOpenRules({
    this.enabled = true,
    this.minimumBackgroundSeconds = 45,
    this.minimumSecondsBetween = 300,
    this.maxPerDay = 4,
    this.skipFirstSessions = 3,
  });
  factory AppOpenRules.fromJson(Map<String, dynamic> j) => AppOpenRules(
        enabled: readBool(j, 'enabled', orElse: true),
        minimumBackgroundSeconds: readInt(j, 'minimumBackgroundSeconds') ?? 45,
        minimumSecondsBetween: readInt(j, 'minimumSecondsBetween') ?? 300,
        maxPerDay: readInt(j, 'maxPerDay') ?? 4,
        skipFirstSessions: readInt(j, 'skipFirstSessions') ?? 3,
      );
  final bool enabled;
  final int minimumBackgroundSeconds;
  final int minimumSecondsBetween;
  final int maxPerDay;
  final int skipFirstSessions;
}

class InterstitialRules {
  const InterstitialRules({
    this.enabled = true,
    this.minimumSecondsBetween = 180,
    this.minimumCompletionsBetween = 2,
    this.minimumLifetimeCompletions = 3,
    this.minimumSessionSeconds = 30,
    this.maxPerDay = 8,
    this.placements = const ['summaryEnter', 'summaryExit', 'afterShare', 'settingsExit'],
  });
  factory InterstitialRules.fromJson(Map<String, dynamic> j) => InterstitialRules(
        enabled: readBool(j, 'enabled', orElse: true),
        minimumSecondsBetween: readInt(j, 'minimumSecondsBetween') ?? 180,
        minimumCompletionsBetween: readInt(j, 'minimumCompletionsBetween') ?? 2,
        minimumLifetimeCompletions: readInt(j, 'minimumLifetimeCompletions') ?? 3,
        minimumSessionSeconds: readInt(j, 'minimumSessionSeconds') ?? 30,
        maxPerDay: readInt(j, 'maxPerDay') ?? 8,
        placements: j.containsKey('placements') ? readStringList(j, 'placements') : const ['summaryEnter', 'summaryExit', 'afterShare', 'settingsExit'],
      );
  final bool enabled;
  final int minimumSecondsBetween;
  final int minimumCompletionsBetween;
  final int minimumLifetimeCompletions;
  final int minimumSessionSeconds;
  final int maxPerDay;
  final List<String> placements;
}

class RewardedRules {
  const RewardedRules({this.enabled = true, this.maxPerDay = 5});
  factory RewardedRules.fromJson(Map<String, dynamic> j) =>
      RewardedRules(enabled: readBool(j, 'enabled', orElse: true), maxPerDay: readInt(j, 'maxPerDay') ?? 5);
  final bool enabled;
  final int maxPerDay;
}

class BannerRules {
  const BannerRules({this.enabled = true, this.refreshSeconds = 60, this.placements = const ['summaryTab']});
  factory BannerRules.fromJson(Map<String, dynamic> j) => BannerRules(
        enabled: readBool(j, 'enabled', orElse: true),
        refreshSeconds: readInt(j, 'refreshSeconds') ?? 60,
        placements: j.containsKey('placements') ? readStringList(j, 'placements') : const ['summaryTab'],
      );
  final bool enabled;
  final int refreshSeconds;
  final List<String> placements;
}

class NativeRules {
  const NativeRules({this.enabled = false, this.firstRow = 6, this.everyRows = 10, this.maxPerScreen = 3, this.placements = const ['minutesList']});
  factory NativeRules.fromJson(Map<String, dynamic> j) => NativeRules(
        enabled: readBool(j, 'enabled'),
        firstRow: readInt(j, 'firstRow') ?? 6,
        everyRows: readInt(j, 'everyRows') ?? 10,
        maxPerScreen: readInt(j, 'maxPerScreen') ?? 3,
        placements: j.containsKey('placements') ? readStringList(j, 'placements') : const ['minutesList'],
      );
  final bool enabled;
  final int firstRow;
  final int everyRows;
  final int maxPerScreen;
  final List<String> placements;
}

class AdsConfig {
  const AdsConfig({
    this.enabled = false,
    this.fullScreenCooldownSeconds = 30,
    this.appOpen = const AppOpenRules(),
    this.interstitial = const InterstitialRules(),
    this.rewarded = const RewardedRules(),
    this.banner = const BannerRules(),
    this.native = const NativeRules(),
  });

  /// Parse the Remote Config string. Any domain that fails keeps its defaults;
  /// an unparseable string yields the full defaults (ads OFF).
  factory AdsConfig.parse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const AdsConfig();
    Map<String, dynamic> j;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const AdsConfig();
      j = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return const AdsConfig();
    }
    T domain<T>(String key, T Function(Map<String, dynamic>) parse, T fallback) {
      final d = readObject(j, key);
      if (d == null) return fallback;
      try {
        return parse(d);
      } catch (_) {
        return fallback;
      }
    }
    return AdsConfig(
      enabled: readBool(j, 'enabled'),
      fullScreenCooldownSeconds: readInt(j, 'fullScreenCooldownSeconds') ?? 30,
      appOpen: domain('appOpen', AppOpenRules.fromJson, const AppOpenRules()),
      interstitial: domain('interstitial', InterstitialRules.fromJson, const InterstitialRules()),
      rewarded: domain('rewarded', RewardedRules.fromJson, const RewardedRules()),
      banner: domain('banner', BannerRules.fromJson, const BannerRules()),
      native: domain('native', NativeRules.fromJson, const NativeRules()),
    );
  }

  final bool enabled;
  final int fullScreenCooldownSeconds;
  final AppOpenRules appOpen;
  final InterstitialRules interstitial;
  final RewardedRules rewarded;
  final BannerRules banner;
  final NativeRules native;
}

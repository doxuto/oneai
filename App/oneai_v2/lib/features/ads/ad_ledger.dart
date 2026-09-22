// Everything the gate needs to know about the past. A value type, JSON in
// storage, mutated only through the record* methods and persisted after each.
import 'dart:convert';

import 'package:one_ai/features/ads/ads_config.dart';

class AdLedger {
  AdLedger({
    this.sessionCount = 0,
    this.sessionStartedAt,
    this.lifetimeCompletions = 0,
    this.completionsSinceInterstitial = 0,
    Map<AdFormat, DateTime>? lastShownAt,
    this.lastFullScreenDismissedAt,
    this.dayKey = '',
    Map<AdFormat, int>? shownToday,
  })  : lastShownAt = lastShownAt ?? {},
        shownToday = shownToday ?? {};

  int sessionCount;
  DateTime? sessionStartedAt;
  int lifetimeCompletions;
  int completionsSinceInterstitial;
  Map<AdFormat, DateTime> lastShownAt;
  DateTime? lastFullScreenDismissedAt;
  /// "yyyy-MM-dd" in local time; when it changes, shownToday is emptied.
  String dayKey;
  Map<AdFormat, int> shownToday;

  static String dayKeyOf(DateTime t) {
    final l = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${l.year}-${two(l.month)}-${two(l.day)}';
  }

  /// Day rollover.
  void normalize(DateTime now) {
    final k = dayKeyOf(now);
    if (k != dayKey) {
      dayKey = k;
      shownToday = {};
    }
  }

  int shownTodayFor(AdFormat f, DateTime now) {
    normalize(now);
    return shownToday[f] ?? 0;
  }

  void recordSessionStart(DateTime at) {
    sessionCount += 1;
    sessionStartedAt = at;
  }

  /// A "done" moment: note created, share completed, … Call BEFORE asking the
  /// interstitial gate.
  void recordCompletion() {
    lifetimeCompletions += 1;
    completionsSinceInterstitial += 1;
  }

  /// Only when the SDK reports the ad actually presented.
  void recordShown(AdFormat f, DateTime at) {
    normalize(at);
    shownToday[f] = (shownToday[f] ?? 0) + 1;
    lastShownAt[f] = at;
    if (f == AdFormat.interstitial) completionsSinceInterstitial = 0;
  }

  /// The cooldown starts here, not at show time.
  void recordFullScreenDismissed(DateTime at) {
    lastFullScreenDismissedAt = at;
  }

  Map<String, Object?> toJson() => {
        'sessionCount': sessionCount,
        'sessionStartedAt': sessionStartedAt?.toIso8601String(),
        'lifetimeCompletions': lifetimeCompletions,
        'completionsSinceInterstitial': completionsSinceInterstitial,
        'lastShownAt': {for (final e in lastShownAt.entries) e.key.name: e.value.toIso8601String()},
        'lastFullScreenDismissedAt': lastFullScreenDismissedAt?.toIso8601String(),
        'dayKey': dayKey,
        'shownToday': {for (final e in shownToday.entries) e.key.name: e.value},
      };

  static AdLedger fromJson(Map<String, dynamic> j) {
    AdFormat? fmt(String n) {
      for (final f in AdFormat.values) {
        if (f.name == n) return f;
      }
      return null;
    }
    final shown = <AdFormat, DateTime>{};
    final rawShown = j['lastShownAt'];
    if (rawShown is Map) {
      for (final e in rawShown.entries) {
        final f = fmt(e.key.toString());
        final t = e.value is String ? DateTime.tryParse(e.value as String) : null;
        if (f != null && t != null) shown[f] = t;
      }
    }
    final today = <AdFormat, int>{};
    final rawToday = j['shownToday'];
    if (rawToday is Map) {
      for (final e in rawToday.entries) {
        final f = fmt(e.key.toString());
        if (f != null && e.value is num) today[f] = (e.value as num).toInt();
      }
    }
    DateTime? d(String k) => j[k] is String ? DateTime.tryParse(j[k] as String) : null;
    int i(String k) => j[k] is num ? (j[k] as num).toInt() : 0;
    return AdLedger(
      sessionCount: i('sessionCount'),
      sessionStartedAt: d('sessionStartedAt'),
      lifetimeCompletions: i('lifetimeCompletions'),
      completionsSinceInterstitial: i('completionsSinceInterstitial'),
      lastShownAt: shown,
      lastFullScreenDismissedAt: d('lastFullScreenDismissedAt'),
      dayKey: j['dayKey'] is String ? j['dayKey'] as String : '',
      shownToday: today,
    );
  }

  String encode() => jsonEncode(toJson());
  static AdLedger decode(String? s) {
    if (s == null || s.isEmpty) return AdLedger();
    try {
      final j = jsonDecode(s);
      return j is Map ? AdLedger.fromJson(Map<String, dynamic>.from(j)) : AdLedger();
    } catch (_) {
      return AdLedger();
    }
  }
}

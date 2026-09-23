import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:one_ai/features/ads/ads_config.dart';

/// Ad unit ids from the `ad_units` Remote Config JSON. Debug builds and any
/// missing key fall back to Google's public TEST ids, so a dev can never
/// click a live ad (docs/08 §3).
class AdUnits {
  const AdUnits._(this._ids);
  final Map<AdFormat, String> _ids;

  static const _test = {
    AdFormat.banner: ('ca-app-pub-3940256099942544/6300978111', 'ca-app-pub-3940256099942544/2934735716'),
    AdFormat.interstitial: ('ca-app-pub-3940256099942544/1033173712', 'ca-app-pub-3940256099942544/4411468910'),
    AdFormat.rewarded: ('ca-app-pub-3940256099942544/5224354917', 'ca-app-pub-3940256099942544/1712485313'),
    AdFormat.appOpen: ('ca-app-pub-3940256099942544/9257395921', 'ca-app-pub-3940256099942544/5575463023'),
    AdFormat.native: ('ca-app-pub-3940256099942544/2247696110', 'ca-app-pub-3940256099942544/3986624511'),
  };

  static AdUnits parse(String? json, {bool? forceTest}) {
    final useTest = forceTest ?? kDebugMode;
    final ios = Platform.isIOS;
    Map<String, dynamic> raw = const {};
    if (!useTest && json != null && json.isNotEmpty) {
      try {
        final decoded = jsonDecode(json);
        if (decoded is Map<String, dynamic>) raw = decoded;
      } on Object catch (_) {}
    }
    final ids = <AdFormat, String>{};
    for (final f in AdFormat.values) {
      final entry = raw[f.name];
      final live = entry is Map ? entry[ios ? 'ios' : 'android'] : null;
      final test = _test[f]!;
      ids[f] = (live is String && live.isNotEmpty && !useTest) ? live : (ios ? test.$2 : test.$1);
    }
    return AdUnits._(ids);
  }

  String operator [](AdFormat f) => _ids[f]!;
}

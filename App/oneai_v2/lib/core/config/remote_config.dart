import 'dart:developer' as dev;

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/features/ads/ads_config.dart';

/// Remote Config, read through one object. Defaults are the SAFE values
/// (ads off, no ad units) so a failed fetch can never turn ads on.
/// `ads_config` / `ad_units` are the two JSON keys from docs/08 §3; the
/// popup keys are carried over from v1 (same names, still live in the console).
class RemoteConfigService {
  RemoteConfigService(this._rc);
  final FirebaseRemoteConfig _rc;

  static const defaults = <String, dynamic>{
    'ads_config': '{"enabled":false}',
    'ad_units': '{}',
    'popup_intro_basic_enabled': false,
    'popup_intro_basic_frequency_hours': 0,
    'popup_intro_basic_text': '',
  };

  /// Never blocks the UI: cached values are used immediately, the fetch runs
  /// with a short timeout and simply logs on failure.
  static Future<RemoteConfigService> init() async {
    final rc = FirebaseRemoteConfig.instance;
    try {
      await rc.setConfigSettings(RemoteConfigSettings(fetchTimeout: const Duration(seconds: 8), minimumFetchInterval: const Duration(hours: 1)));
      await rc.setDefaults(defaults);
      await rc.fetchAndActivate();
    } on Object catch (e) {
      dev.log('remote config fetch failed; using cache/defaults', name: 'config', error: e);
    }
    return RemoteConfigService(rc);
  }

  AdsConfig get adsConfig => AdsConfig.parse(_rc.getString('ads_config'));
  String get adUnitsJson => _rc.getString('ad_units');

  bool get popupIntroBasicEnabled => _rc.getBool('popup_intro_basic_enabled');
  int get popupIntroBasicFrequencyHours => _rc.getInt('popup_intro_basic_frequency_hours');
  String get popupIntroBasicText => _rc.getString('popup_intro_basic_text');
}

/// Resolves once per app run; screens `watch` it and treat loading as defaults.
final remoteConfigProvider = FutureProvider<RemoteConfigService>((_) => RemoteConfigService.init());

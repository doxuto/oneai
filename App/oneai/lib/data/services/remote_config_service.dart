import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:codebase_ai/data/services/base/base_long_init_service.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

abstract class RemoteConfigService {
  bool get adBannerEnabled;
  int get adBannerRefreshRateSeconds;
  bool get adInterstitialEnabled;
  int get adLoadTimeoutSeconds;
  int get adOpenAppBackgroundThresholdMinutes;
  int get adFullscreenGlobalFreqSeconds;
  bool get adOpenAppEnabled;
  int get adRewardedDailyLimit;
  bool get adRewardedEnabled;
  String get adUnitBanner;
  String get adUnitInterstitialPreSummary;
  String get adUnitInterstitialAfterShare;
  String get adUnitInterstitialSettingsExit;
  String get adUnitInterstitialSummaryExit;
  String get adUnitOpenApp;
  String get adUnitRewarded;
  bool get popupIntroBasicEnabled;
  int get popupIntroBasicFrequencyHours;
  String get popupIntroBasicText;
  String get adToastFreqLimitMessage;
  int get adPreloadTimeoutMinutes;

  Future<void> waitForInitialization();
}

class FirebaseRemoteConfigService extends BaseLongInitService implements RemoteConfigService {
  final _remoteConfig = FirebaseRemoteConfig.instance;
  late StreamSubscription<RemoteConfigUpdate> _subscription;

  FirebaseRemoteConfigService() : super('FirebaseRemoteConfigService');

  @override
  Future<void> waitForInitialization() => super.checkInitialization();

  @override
  Future<void> performInitialization() async {
    log.info('Initializing Firebase Remote Config');
    try {
      await _remoteConfig.setDefaults({
        'ad_unit_banner': '{"Android":"","iOS":""}',
        'ad_unit_interstitial_pre_summary': '{"Android":"","iOS":""}',
        'ad_unit_open_app': '{"Android":"","iOS":""}',
        'ad_unit_rewarded': '{"Android":"","iOS":""}',
        'ad_unit_interstitial_after_share': '{"Android":"","iOS":""}',
        'ad_unit_interstitial_settings_exit': '{"Android":"","iOS":""}',
        'ad_unit_interstitial_summary_exit': '{"Android":"","iOS":""}',
        'popup_intro_basic_enabled': 'true',
        'popup_intro_basic_frequency_hours': '0',
        'popup_intro_basic_text':
            "Welcome to the One AI Basic Plan!\\nWe\u0027re happy to have you here. To get you started, here’s what our free plan includes:\\n\\n✅ Free Daily Credits: You receive a new set of free credits every day to transcribe and summarize your audio.\\n🎧 30-Minute Limit: Each audio file can be up to 30 minutes long.\\n💰 Need More? Earn extra credits anytime just by watching a short ad.\\n\\nTo keep our core features free, our service is supported by advertisements and our Premium members. Your understanding helps us maintain and grow the app.\\nIf you\u0027d like to enjoy an enhanced experience and support us further, please consider upgrading.",
        'ad_load_timeout_seconds': '5',
        'ad_open_app_background_threshold_minutes': '30',
        'ad_fullscreen_global_freq_seconds': '120',
        'ad_rewarded_daily_limit': '5',
        'ad_banner_refresh_rate_seconds': '60',
        'ad_banner_enabled': 'true',
        'ad_interstitial_enabled': 'true',
        'ad_rewarded_enabled': 'true',
        'ad_open_app_enabled': 'true',
        'ad_toast_freq_limit_message': 'You just watched an ad. Please try again in a moment.',
        'ad_preload_timeout_minutes': '60',
      });
      await _remoteConfig.setConfigSettings(
        RemoteConfigSettings(fetchTimeout: const Duration(minutes: 1), minimumFetchInterval: const Duration(hours: 1)),
      );
      await _remoteConfig.fetchAndActivate();

      // Listen for updates in Remote Config
      _subscription = _remoteConfig.onConfigUpdated.listen(
        _onConfigUpdated,
        onDone: _updateStreamOnDone,
        onError: _updateStreamOnError,
      );

      log.info('Firebase Remote Config initialized successfully');
    } catch (e) {
      log.severe('Failed to initialize Firebase Remote Config: $e');
    }
  }

  Future<void> _onConfigUpdated(RemoteConfigUpdate update) async {
    log.info('Firebase Remote Config _onConfigUpdated');
    await _remoteConfig.activate();
  }

  void _updateStreamOnDone() {
    _subscription.cancel();
  }

  void _updateStreamOnError(dynamic error) {
    log.severe('Failed to update Firebase Remote Config stream: $error');
  }

  @override
  bool get adBannerEnabled => _remoteConfig.getBool('ad_banner_enabled');

  @override
  int get adBannerRefreshRateSeconds => _remoteConfig.getInt('ad_banner_refresh_rate_seconds');

  @override
  bool get adInterstitialEnabled => _remoteConfig.getBool('ad_interstitial_enabled');

  @override
  int get adLoadTimeoutSeconds => _remoteConfig.getInt('ad_load_timeout_seconds');

  @override
  int get adOpenAppBackgroundThresholdMinutes => _remoteConfig.getInt('ad_open_app_background_threshold_minutes');

  @override
  int get adFullscreenGlobalFreqSeconds => _remoteConfig.getInt('ad_fullscreen_global_freq_seconds');

  @override
  bool get adOpenAppEnabled => _remoteConfig.getBool('ad_open_app_enabled');

  @override
  int get adRewardedDailyLimit => _remoteConfig.getInt('ad_rewarded_daily_limit');

  @override
  bool get adRewardedEnabled => _remoteConfig.getBool('ad_rewarded_enabled');

  @override
  String get adUnitBanner => getStringValueFromPlatformMap('ad_unit_banner');

  @override
  String get adUnitInterstitialPreSummary => getStringValueFromPlatformMap('ad_unit_interstitial_pre_summary');

  @override
  String get adUnitInterstitialAfterShare => getStringValueFromPlatformMap('ad_unit_interstitial_after_share');

  @override
  String get adUnitInterstitialSettingsExit => getStringValueFromPlatformMap('ad_unit_interstitial_settings_exit');

  @override
  String get adUnitInterstitialSummaryExit => getStringValueFromPlatformMap('ad_unit_interstitial_summary_exit');

  @override
  String get adUnitOpenApp => getStringValueFromPlatformMap('ad_unit_open_app');

  @override
  String get adUnitRewarded => getStringValueFromPlatformMap('ad_unit_rewarded');

  @override
  bool get popupIntroBasicEnabled => _remoteConfig.getBool('popup_intro_basic_enabled');

  @override
  int get popupIntroBasicFrequencyHours => _remoteConfig.getInt('popup_intro_basic_frequency_hours');

  @override
  String get popupIntroBasicText => _remoteConfig.getString('popup_intro_basic_text').replaceAll(r'\n', '\n');

  @override
  String get adToastFreqLimitMessage => _remoteConfig.getString('ad_toast_freq_limit_message').replaceAll(r'\n', '\n');

  @override
  int get adPreloadTimeoutMinutes => _remoteConfig.getInt('ad_preload_timeout_minutes');

  String getStringValueFromPlatformMap(String key) {
    try {
      final jsonStr = _remoteConfig.getString(key);
      final map = json.decode(jsonStr) as Map<String, dynamic>;
      if (Platform.isAndroid) {
        return (map['Android'] ?? '').toString();
      } else if (Platform.isIOS) {
        return (map['iOS'] ?? '').toString();
      }
    } catch (e) {
      log.warning('Failed to parse $key: $e');
    }
    return '';
  }
}

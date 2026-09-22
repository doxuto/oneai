import 'dart:ui';

import 'package:codebase_ai/domain/models/theme_type_model.dart';
import 'package:codebase_ai/utils/result.dart';
import 'package:logging/logging.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for handling persistent preferences using SharedPreferences
class SharedPreferencesService {
  final _log = Logger('SharedPreferencesService');

  /// Key for storing user locale preference
  static const String _appLocale = 'APP_LOCALE';

  /// Key for storing user theme preference
  static const String _appTheme = 'APP_THEME';

  /// Key for storing login method
  static const String _loginMethod = 'LOGIN_METHOD';

  /// Key for storing audio language
  static const String _audioLanguage = 'AUDIO_LANGUAGE';

  /// Key for storing summary language
  static const String _summaryLanguage = 'SUMMARY_LANGUAGE';

  static const String _showCongratulationDialog = 'SHOW_CONGRATULATION_DIALOG';

  /// Key for storing rewarded ad daily counter
  static const String _rewardedAdShownToday = 'REWARDED_AD_SHOWN_TODAY';

  /// Key for storing last reset date for rewarded ad counter
  static const String _rewardedAdLastResetDate = 'REWARDED_AD_LAST_RESET_DATE';

  /// Key for storing last shown time of full screen ad
  /// This is used to prevent showing the ad too frequently
  static const String _fullScreenAdLastShownTime = 'FULL_SCREEN_AD_LAST_SHOWN_TIME';

  /// Key for storing last shown time of intro basic
  /// This is used to prevent showing the popup too frequently
  static const String _introBasicLastShownTime = 'INTRO_BASIC_LAST_SHOWN_TIME';

  /// A simple wrapper around SharedPreferences to use with async/await
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  /// Retrieves the user's preferred locale from storage
  ///
  /// Returns the stored locale or defaults to English if none is found
  Future<Result<Locale>> getLocale() async {
    _log.info('Getting stored locale');
    try {
      final String? locale = await _preferences.getString(_appLocale);
      if (locale != null) {
        final List<String> localeParts = locale.split('_');
        final Locale result = Locale(localeParts[0], localeParts.length > 1 ? localeParts[1] : '');
        _log.info('Retrieved locale: $result');
        return Result.ok(result);
      } else {
        _log.info('No stored locale found, returning default: en');
        return const Result.ok(Locale('en', ''));
      }
    } on Exception catch (e) {
      _log.warning('Error getting locale: $e');
      return Result.error(e);
    }
  }

  /// Saves the user's preferred locale to storage
  Future<Result<void>> setLocale(Locale locale) async {
    try {
      final String localeString = '${locale.languageCode}_${locale.countryCode}';
      _log.info('Setting locale to: $localeString');
      await _preferences.setString(_appLocale, localeString);
      _log.info('Locale saved successfully');
      return const Result.ok(null);
    } on Exception catch (e) {
      _log.warning('Error setting locale: $e');
      return Result.error(e);
    }
  }

  /// Retrieves the user's preferred theme from storage
  ///
  /// Returns the stored theme or defaults to system theme if none is found
  Future<Result<ThemeType>> getTheme() async {
    _log.info('Getting stored theme');
    try {
      final String? theme = await _preferences.getString(_appTheme);
      if (theme != null) {
        final ThemeType result = ThemeType.values.byName(theme);
        _log.info('Retrieved theme: ${result.name}');
        return Result.ok(result);
      } else {
        _log.info('No stored theme found, returning default: system');
        return const Result.ok(ThemeType.system);
      }
    } on Exception catch (e) {
      _log.warning('Error getting theme: $e');
      return Result.error(e);
    }
  }

  /// Saves the user's preferred theme to storage
  Future<Result<void>> setTheme(ThemeType theme) async {
    try {
      _log.info('Setting theme to: ${theme.name}');
      await _preferences.setString(_appTheme, theme.name);
      _log.info('Theme saved successfully');
      return const Result.ok(null);
    } on Exception catch (e) {
      _log.warning('Error setting theme: $e');
      return Result.error(e);
    }
  }

  /// Saves the user's login method to storage
  Future<Result<void>> setLoginMethod(String method) async {
    try {
      _log.info('Setting login method to: $method');
      await _preferences.setString(_loginMethod, method);
      _log.info('Login method saved successfully');
      return const Result.ok(null);
    } on Exception catch (e) {
      _log.warning('Error setting login method: $e');
      return Result.error(e);
    }
  }

  /// Retrieves the user's login method from storage
  Future<Result<String?>> getLoginMethod() async {
    try {
      final String? method = await _preferences.getString(_loginMethod);
      _log.info('Retrieved login method: $method');
      return Result.ok(method);
    } on Exception catch (e) {
      _log.warning('Error getting login method: $e');
      return Result.error(e);
    }
  }

  /// Saves the user's audio language to storage
  Future<void> setAudioLanguage(String language) async {
    await _preferences.setString(_audioLanguage, language);
  }

  /// Retrieves the user's audio language from storage
  Future<String?> getAudioLanguage() async => _preferences.getString(_audioLanguage);

  /// Saves the user's summary language to storage
  Future<void> setSummaryLanguage(String language) async {
    await _preferences.setString(_summaryLanguage, language);
  }

  /// Retrieves the user's summary language from storage
  Future<String?> getSummaryLanguage() async => _preferences.getString(_summaryLanguage);

  /// Saves whether to show the congratulation dialog
  Future<void> markShowCongratulationDialog() async {
    await _preferences.setBool(_showCongratulationDialog, false);
    _log.info('Show congratulation dialog marked as false');
  }

  /// Retrieves whether to show the congratulation dialog
  Future<bool> getShowCongratulationDialog() async {
    final bool? show = await _preferences.getBool(_showCongratulationDialog);
    _log.info('Retrieved show congratulation dialog: $show');
    return show ?? true; // Default to true if not set
  }

  /// Get the number of rewarded ads shown today
  Future<int> getRewardedAdShownToday() async {
    final value = await _preferences.getInt(_rewardedAdShownToday);
    return value ?? 0;
  }

  /// Set the number of rewarded ads shown today
  Future<void> setRewardedAdShownToday(int count) async {
    await _preferences.setInt(_rewardedAdShownToday, count);
  }

  /// Get the last reset date for rewarded ad counter (as toIso8601String)
  Future<String?> getRewardedAdLastResetDate() async => _preferences.getString(_rewardedAdLastResetDate);

  /// Set the last reset date for rewarded ad counter (as toIso8601String)
  Future<void> setRewardedAdLastResetDate(String date) => _preferences.setString(_rewardedAdLastResetDate, date);

  /// Get the last shown time of full screen ad (as toIso8601String)
  Future<String?> getFullScreenAdLastShownTime() async => _preferences.getString(_fullScreenAdLastShownTime);

  /// Set the last shown time of full screen ad (as toIso8601String)
  /// This is used to prevent showing the ad too frequently
  Future<void> setFullScreenAdLastShownTime(String time) => _preferences.setString(_fullScreenAdLastShownTime, time);

  /// Get the last shown time of intro basic (as toIso8601String)
  Future<String?> getIntroBasicLastShownTime() async => _preferences.getString(_introBasicLastShownTime);

  /// Set the last shown time of intro basic (as toIso8601String)
  /// This is used to prevent showing the popup too frequently
  Future<void> setIntroBasicLastShownTime(String time) => _preferences.setString(_introBasicLastShownTime, time);
}

import 'dart:ui';

import 'package:codebase_ai/data/services/shared_preferences_service.dart';
import 'package:codebase_ai/utils/result.dart';
import 'package:logging/logging.dart';

/// Repository for managing language preferences
abstract class LanguageRepository {
  /// Get the current locale
  Future<Result<Locale>> getLocale();

  /// Set the locale
  Future<Result<void>> setLocale(Locale locale);
}

/// Implementation of [LanguageRepository] that uses [SharedPreferencesService]
class LanguageRepositoryImpl implements LanguageRepository {
  final _log = Logger('LanguageRepositoryImpl');
  final SharedPreferencesService _preferencesService;

  /// Creates a [LanguageRepositoryImpl] with the provided [SharedPreferencesService]
  LanguageRepositoryImpl({required SharedPreferencesService preferencesService})
    : _preferencesService = preferencesService;

  @override
  Future<Result<Locale>> getLocale() async {
    _log.info('Getting current locale from preferences');
    return _preferencesService.getLocale();
  }

  @override
  Future<Result<void>> setLocale(Locale locale) async {
    _log.info('Setting locale to: ${locale.languageCode}_${locale.countryCode}');
    return _preferencesService.setLocale(locale);
  }
}

import 'package:codebase_ai/data/services/shared_preferences_service.dart';
import 'package:codebase_ai/domain/models/theme_type_model.dart';
import 'package:codebase_ai/utils/result.dart';
import 'package:logging/logging.dart';

/// Repository for managing theme preferences
abstract class ThemeRepository {
  /// Get the current theme
  Future<Result<ThemeType>> getTheme();

  /// Set the theme
  Future<Result<void>> setTheme(ThemeType theme);
}

/// Implementation of [ThemeRepository] that uses [SharedPreferencesService]
class ThemeRepositoryImpl implements ThemeRepository {
  final _log = Logger('ThemeRepositoryImpl');
  final SharedPreferencesService _preferencesService;

  /// Creates a [ThemeRepositoryImpl] with the provided [SharedPreferencesService]
  ThemeRepositoryImpl({required SharedPreferencesService preferencesService})
    : _preferencesService = preferencesService;

  @override
  Future<Result<ThemeType>> getTheme() async {
    _log.info('Getting current theme from preferences');
    return _preferencesService.getTheme();
  }

  @override
  Future<Result<void>> setTheme(ThemeType theme) async {
    _log.info('Setting theme to: ${theme.name}');
    return _preferencesService.setTheme(theme);
  }
}

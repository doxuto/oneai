import 'package:bloc/bloc.dart';
import 'package:codebase_ai/data/repositories/theme_repository.dart';
import 'package:codebase_ai/domain/models/theme_type_model.dart';
import 'package:codebase_ai/ui/core/themes/dark_theme.dart';
import 'package:codebase_ai/ui/core/themes/light_theme.dart';
import 'package:codebase_ai/ui/core/themes/theme_helpers.dart';
import 'package:codebase_ai/utils/result.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:logging/logging.dart';

part 'theme_bloc.freezed.dart';

@freezed
sealed class ThemeEvent with _$ThemeEvent {
  const factory ThemeEvent.initial() = _Initial;

  const factory ThemeEvent.changed({required ThemeType themeType}) = _Changed;
}

@freezed
sealed class ThemeState with _$ThemeState {
  const factory ThemeState({required ThemeType themeType, required ThemeData themeData, required bool isDarkMode}) =
      _ThemeState;

  factory ThemeState.initial() {
    // Default to system theme
    const themeType = ThemeType.system;

    // Determine if dark mode based on platform brightness
    final brightness = SchedulerBinding.instance.platformDispatcher.platformBrightness;
    final isDarkMode = brightness == Brightness.dark;

    // Set theme data based on brightness
    final themeData = isDarkMode ? darkTheme : lightTheme;

    return ThemeState(themeType: themeType, themeData: themeData, isDarkMode: isDarkMode);
  }
}

class ThemeBloc extends Bloc<ThemeEvent, ThemeState> {
  final _log = Logger('ThemeBloc');
  final ThemeRepository _themeRepository;

  ThemeBloc({required ThemeRepository themeRepository})
    : _themeRepository = themeRepository,
      super(ThemeState.initial()) {
    on<_Initial>(_onThemeInitial);
    on<_Changed>(_onThemeChanged);
  }

  Future<void> _onThemeInitial(_Initial event, Emitter<ThemeState> emit) async {
    final themeResult = await _themeRepository.getTheme();

    switch (themeResult) {
      case Ok(value: final value):
        _log.info('Loaded initial theme from repository: ${value.name}');
        add(ThemeEvent.changed(themeType: value));
      case Error(error: final error):
        _log.warning('Failed to load initial theme: $error');
    }
  }

  Future<void> _onThemeChanged(_Changed event, Emitter<ThemeState> emit) async {
    final themeType = event.themeType;

    // Don't emit if the theme hasn't changed
    if (state.themeType == themeType) {
      return;
    }

    bool isDarkMode;
    ThemeData themeData;

    // Determine theme data and dark mode status based on theme type
    switch (themeType) {
      case ThemeType.light:
        themeData = lightTheme;
        isDarkMode = false;
        break;
      case ThemeType.dark:
        themeData = darkTheme;
        isDarkMode = true;
        break;
      case ThemeType.system:
        final brightness = SchedulerBinding.instance.platformDispatcher.platformBrightness;
        isDarkMode = brightness == Brightness.dark;
        themeData = isDarkMode ? darkTheme : lightTheme;
        break;
    }

    // Update system UI overlay style using ThemeHelpers
    ThemeHelpers.updateSystemUiOverlayDirect(
      isDark: isDarkMode,
      themeData: themeData,
      statusBarColor: Colors.transparent,
    );

    // Save theme preference
    final saveResult = await _themeRepository.setTheme(themeType);

    switch (saveResult) {
      case Ok():
        emit(state.copyWith(themeType: themeType, themeData: themeData, isDarkMode: isDarkMode));
        _log.info('Theme changed to: ${themeType.name}');
      case Error(error: final error):
        _log.severe('Failed to save theme preference: $error');
    }
  }
}

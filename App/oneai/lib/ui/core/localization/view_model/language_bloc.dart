import 'package:bloc/bloc.dart';
import 'package:codebase_ai/data/repositories/language_repository.dart';
import 'package:codebase_ai/ui/core/localization/generated/l10n.dart';
import 'package:codebase_ai/utils/result.dart';
import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:logging/logging.dart';

part 'language_bloc.freezed.dart';

@freezed
sealed class LanguageEvent with _$LanguageEvent {
  const factory LanguageEvent.initial() = _Initial;

  const factory LanguageEvent.changed({required Locale locale}) = _Changed;
}

@freezed
sealed class LanguageState with _$LanguageState {
  const factory LanguageState({required Locale locale}) = _LanguageState;

  factory LanguageState.initial() => const LanguageState(locale: Locale('en'));
}

class LanguageBloc extends Bloc<LanguageEvent, LanguageState> {
  final _log = Logger('LanguageBloc');
  final LanguageRepository _languageRepository;

  LanguageBloc({required LanguageRepository languageRepository})
    : _languageRepository = languageRepository,
      super(LanguageState.initial()) {
    on<_Initial>(_onLanguageInitial);
    on<_Changed>(_onLanguageChanged);
  }

  Future<void> _onLanguageInitial(_Initial event, Emitter<LanguageState> emit) async {
    final localeResult = await _languageRepository.getLocale();

    switch (localeResult) {
      case Ok(value: final locale):
        _log.info('Loaded initial locale from repository: $locale');
        add(LanguageEvent.changed(locale: locale));
      case Error(error: final error):
        _log.warning('Failed to load initial locale: $error');
    }
  }

  Future<void> _onLanguageChanged(_Changed event, Emitter<LanguageState> emit) async {
    final locale = event.locale;

    // Don't emit if the locale hasn't changed
    if (state.locale == locale) {
      return;
    }

    // Save the locale to repository
    final saveResult = await _languageRepository.setLocale(locale);

    switch (saveResult) {
      case Ok():
        try {
          // Initialize the locale using the Intl plugin
          await AppLocalizations.load(locale);

          emit(state.copyWith(locale: locale));
          _log.info('Language changed to: ${locale.languageCode}_${locale.countryCode}');
        } on Exception catch (e) {
          _log.severe('Failed to initialize language: $e');
        }
      case Error(error: final error):
        _log.severe('Failed to save language preference: $error');
    }
  }
}

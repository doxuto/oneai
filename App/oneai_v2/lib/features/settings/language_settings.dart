import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/features/transcription/transcription_language.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The two language choices from Settings (also editable per note on the
/// record / upload screens). Per-device, like v1.
class LanguageSettings {
  const LanguageSettings({required this.audioLanguage, required this.summaryLanguage});

  /// What the audio is in; `auto` lets Scribe detect.
  final TranscriptionLanguage audioLanguage;

  /// What the summary, chat and generated artifacts are written in. Never `auto`.
  final TranscriptionLanguage summaryLanguage;

  /// Sent as `startTranscription.summaryLanguage` — the English name reads
  /// better inside the summarise prompt ("write in Vietnamese").
  String get summaryLanguageForServer => summaryLanguage.englishName;

  /// Sent as `languageCode` to chat / generate* — ISO-639-3.
  String get aiLanguageCode => summaryLanguage.code;

  LanguageSettings copyWith({TranscriptionLanguage? audioLanguage, TranscriptionLanguage? summaryLanguage}) =>
      LanguageSettings(
        audioLanguage: audioLanguage ?? this.audioLanguage,
        summaryLanguage: summaryLanguage ?? this.summaryLanguage,
      );

  /// Default for a fresh install: audio auto-detected, summary in the device
  /// language when we support it, else English.
  static LanguageSettings defaultsFor(String? deviceLanguageCode) => LanguageSettings(
        audioLanguage: TranscriptionLanguage.auto,
        summaryLanguage: fromDeviceLanguage(deviceLanguageCode),
      );

  static TranscriptionLanguage fromDeviceLanguage(String? iso6391) {
    final l = _iso6391To3[iso6391?.toLowerCase()];
    if (l == null) return TranscriptionLanguage.english;
    final parsed = TranscriptionLanguage.fromCode(l);
    return parsed == TranscriptionLanguage.auto ? TranscriptionLanguage.english : parsed;
  }

  /// Parses anything v1 or v2 may have stored: an ISO-639-3 code ("vie"),
  /// v1's enum name ("vietnamese", "autodetect") or "auto-detect".
  static TranscriptionLanguage? parseStored(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final s = raw.trim().toLowerCase();
    if (s == 'autodetect' || s == 'auto-detect' || s == 'auto') return TranscriptionLanguage.auto;
    for (final l in TranscriptionLanguage.values) {
      if (l.code == s || l.name == s || l.englishName.toLowerCase() == s) return l;
    }
    return null;
  }

  static const _iso6391To3 = {
    'en': 'eng', 'vi': 'vie', 'es': 'spa', 'fr': 'fra', 'de': 'deu', 'ja': 'jpn', 'ko': 'kor', 'zh': 'zho',
    'pt': 'por', 'it': 'ita', 'ru': 'rus', 'ar': 'ara', 'hi': 'hin', 'id': 'ind', 'th': 'tha', 'tr': 'tur',
    'nl': 'nld', 'pl': 'pol', 'uk': 'ukr', 'ms': 'msa', 'fil': 'fil', 'tl': 'fil', 'bn': 'ben', 'ta': 'tam',
    'sv': 'swe', 'da': 'dan', 'fi': 'fin', 'nb': 'nor', 'no': 'nor', 'cs': 'ces', 'el': 'ell', 'he': 'heb',
    'hu': 'hun', 'ro': 'ron', 'sk': 'slk', 'bg': 'bul', 'hr': 'hrv', 'ca': 'cat', 'et': 'est', 'is': 'isl',
    'kn': 'kan', 'lt': 'lit', 'lv': 'lav', 'mr': 'mar', 'sl': 'slv', 'te': 'tel', 'ur': 'urd',
  };
}

abstract interface class LanguageSettingsStore {
  Future<LanguageSettings?> read();
  Future<void> write(LanguageSettings s);
}

class PrefsLanguageSettingsStore implements LanguageSettingsStore {
  const PrefsLanguageSettingsStore();

  // v1 keys, so an upgrade keeps the user's choices.
  static const audioKey = 'AUDIO_LANGUAGE';
  static const summaryKey = 'SUMMARY_LANGUAGE';

  @override
  Future<LanguageSettings?> read() async {
    try {
      final p = await SharedPreferences.getInstance();
      final audio = LanguageSettings.parseStored(p.getString(audioKey));
      final summary = LanguageSettings.parseStored(p.getString(summaryKey));
      if (audio == null && summary == null) return null;
      final defaults = LanguageSettings.defaultsFor(deviceLanguageCode());
      return LanguageSettings(
        audioLanguage: audio ?? defaults.audioLanguage,
        summaryLanguage: (summary == null || summary == TranscriptionLanguage.auto) ? defaults.summaryLanguage : summary,
      );
    } on Object catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(LanguageSettings s) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(audioKey, s.audioLanguage.code);
      await p.setString(summaryKey, s.summaryLanguage.code);
    } on Object catch (_) {
      // Per-device convenience; losing it is not an error.
    }
  }

  static String? deviceLanguageCode() {
    try {
      return PlatformDispatcher.instance.locale.languageCode;
    } on Object catch (_) {
      return null;
    }
  }
}

class InMemoryLanguageSettingsStore implements LanguageSettingsStore {
  InMemoryLanguageSettingsStore([this.value]);
  LanguageSettings? value;
  int writes = 0;
  @override
  Future<LanguageSettings?> read() async => value;
  @override
  Future<void> write(LanguageSettings s) async {
    value = s;
    writes++;
  }
}

// ---- Wiring ----

final languageSettingsStoreProvider = Provider<LanguageSettingsStore>((_) => const PrefsLanguageSettingsStore());

/// Device language, overridable in tests.
final deviceLanguageCodeProvider = Provider<String?>((_) => PrefsLanguageSettingsStore.deviceLanguageCode());

final languageSettingsProvider = NotifierProvider<LanguageSettingsController, LanguageSettings>(LanguageSettingsController.new);

class LanguageSettingsController extends Notifier<LanguageSettings> {
  @override
  LanguageSettings build() {
    unawaited(Future<void>.microtask(_load));
    return LanguageSettings.defaultsFor(ref.watch(deviceLanguageCodeProvider));
  }

  Future<void> _load() async {
    final stored = await ref.read(languageSettingsStoreProvider).read();
    if (stored != null) state = stored;
  }

  Future<void> setAudioLanguage(TranscriptionLanguage l) => _set(state.copyWith(audioLanguage: l));

  /// `auto` is not a summary language; ignored.
  Future<void> setSummaryLanguage(TranscriptionLanguage l) async {
    if (l == TranscriptionLanguage.auto) return;
    await _set(state.copyWith(summaryLanguage: l));
  }

  Future<void> _set(LanguageSettings s) async {
    state = s;
    await ref.read(languageSettingsStoreProvider).write(s);
  }
}

/// ISO-639-3 code the AI features send as `languageCode`.
final aiLanguageCodeProvider = Provider<String>((ref) => ref.watch(languageSettingsProvider).aiLanguageCode);

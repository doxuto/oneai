import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/features/settings/language_settings.dart';
import 'package:one_ai/features/transcription/transcription_language.dart';

Future<void> settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('parseStored', () {
    test('accepts v2 codes, v1 enum names and auto spellings', () {
      expect(LanguageSettings.parseStored('vie'), TranscriptionLanguage.vietnamese);
      expect(LanguageSettings.parseStored('vietnamese'), TranscriptionLanguage.vietnamese);
      expect(LanguageSettings.parseStored('Vietnamese'), TranscriptionLanguage.vietnamese);
      expect(LanguageSettings.parseStored('autodetect'), TranscriptionLanguage.auto);
      expect(LanguageSettings.parseStored('auto-detect'), TranscriptionLanguage.auto);
      expect(LanguageSettings.parseStored('klingon'), isNull);
      expect(LanguageSettings.parseStored(null), isNull);
      expect(LanguageSettings.parseStored(''), isNull);
    });
  });

  group('defaults', () {
    test('summary follows the device language when supported, else English', () {
      expect(LanguageSettings.defaultsFor('vi').summaryLanguage, TranscriptionLanguage.vietnamese);
      expect(LanguageSettings.defaultsFor('ES').summaryLanguage, TranscriptionLanguage.spanish);
      expect(LanguageSettings.defaultsFor('xx').summaryLanguage, TranscriptionLanguage.english);
      expect(LanguageSettings.defaultsFor(null).summaryLanguage, TranscriptionLanguage.english);
      expect(LanguageSettings.defaultsFor('vi').audioLanguage, TranscriptionLanguage.auto);
    });

    test('server representations', () {
      final s = LanguageSettings.defaultsFor('vi');
      expect(s.summaryLanguageForServer, 'Vietnamese');
      expect(s.aiLanguageCode, 'vie');
    });
  });

  group('controller', () {
    ProviderContainer make(InMemoryLanguageSettingsStore store, {String? device = 'en'}) => ProviderContainer.test(overrides: [
          languageSettingsStoreProvider.overrideWithValue(store),
          deviceLanguageCodeProvider.overrideWithValue(device),
        ]);

    test('starts with defaults, then adopts what is stored', () async {
      final store = InMemoryLanguageSettingsStore(
        const LanguageSettings(audioLanguage: TranscriptionLanguage.japanese, summaryLanguage: TranscriptionLanguage.english),
      );
      final c = make(store, device: 'vi');
      c.listen(languageSettingsProvider, (_, __) {});
      expect(c.read(languageSettingsProvider).summaryLanguage, TranscriptionLanguage.vietnamese);
      await settle();
      expect(c.read(languageSettingsProvider).audioLanguage, TranscriptionLanguage.japanese);
      expect(c.read(languageSettingsProvider).summaryLanguage, TranscriptionLanguage.english);
      expect(c.read(aiLanguageCodeProvider), 'eng');
    });

    test('setters persist; auto is refused as a summary language', () async {
      final store = InMemoryLanguageSettingsStore();
      final c = make(store);
      c.listen(languageSettingsProvider, (_, __) {});
      await settle();
      await c.read(languageSettingsProvider.notifier).setSummaryLanguage(TranscriptionLanguage.vietnamese);
      await c.read(languageSettingsProvider.notifier).setAudioLanguage(TranscriptionLanguage.vietnamese);
      await c.read(languageSettingsProvider.notifier).setSummaryLanguage(TranscriptionLanguage.auto);
      expect(store.writes, 2);
      expect(store.value?.summaryLanguage, TranscriptionLanguage.vietnamese);
      expect(store.value?.audioLanguage, TranscriptionLanguage.vietnamese);
      expect(c.read(aiLanguageCodeProvider), 'vie');
    });
  });
}

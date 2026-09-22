/// Languages the transcription can be told to expect. Codes are ISO-639-3 as
/// ElevenLabs Scribe takes them; `auto` lets the model detect. Carried over
/// from v1's Language enum (the app-UI locale is a separate concept).
enum TranscriptionLanguage {
  auto('auto', 'Auto Detect'),
  arabic('ara', 'Arabic'),
  bengali('ben', 'Bengali'),
  bulgarian('bul', 'Bulgarian'),
  catalan('cat', 'Catalan'),
  chinese('zho', 'Chinese'),
  croatian('hrv', 'Croatian'),
  czech('ces', 'Czech'),
  danish('dan', 'Danish'),
  dutch('nld', 'Dutch'),
  english('eng', 'English'),
  estonian('est', 'Estonian'),
  filipino('fil', 'Filipino'),
  finnish('fin', 'Finnish'),
  french('fra', 'French'),
  german('deu', 'German'),
  greek('ell', 'Greek'),
  hebrew('heb', 'Hebrew'),
  hindi('hin', 'Hindi'),
  hungarian('hun', 'Hungarian'),
  icelandic('isl', 'Icelandic'),
  indonesian('ind', 'Indonesian'),
  italian('ita', 'Italian'),
  japanese('jpn', 'Japanese'),
  kannada('kan', 'Kannada'),
  korean('kor', 'Korean'),
  latvian('lav', 'Latvian'),
  lithuanian('lit', 'Lithuanian'),
  malay('msa', 'Malay'),
  malayalam('mal', 'Malayalam'),
  marathi('mar', 'Marathi'),
  norwegian('nor', 'Norwegian'),
  polish('pol', 'Polish'),
  portuguese('por', 'Portuguese'),
  punjabi('pan', 'Punjabi'),
  romanian('ron', 'Romanian'),
  russian('rus', 'Russian'),
  serbian('srp', 'Serbian'),
  slovak('slk', 'Slovak'),
  slovenian('slv', 'Slovenian'),
  spanish('spa', 'Spanish'),
  swedish('swe', 'Swedish'),
  tamil('tam', 'Tamil'),
  telugu('tel', 'Telugu'),
  thai('tha', 'Thai'),
  turkish('tur', 'Turkish'),
  ukrainian('ukr', 'Ukrainian'),
  urdu('urd', 'Urdu'),
  uzbek('uzb', 'Uzbek'),
  vietnamese('vie', 'Vietnamese');

  const TranscriptionLanguage(this.code, this.englishName);

  /// What the server receives.
  final String code;
  /// Fallback label; screens should prefer the localized name.
  final String englishName;

  /// Languages a summary can be written in — everything but `auto`.
  static List<TranscriptionLanguage> get summaryChoices =>
      values.where((l) => l != TranscriptionLanguage.auto).toList();

  static TranscriptionLanguage fromCode(String? code) {
    if (code == null) return TranscriptionLanguage.auto;
    // v1 stored "auto-detect".
    if (code == 'auto-detect') return TranscriptionLanguage.auto;
    for (final l in values) {
      if (l.code == code) return l;
    }
    return TranscriptionLanguage.auto;
  }
}

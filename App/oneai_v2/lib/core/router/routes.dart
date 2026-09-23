/// Route paths carried over from v1 so deep links and notification taps that
/// already exist keep working (docs/07-APP-UI-FLOW-SPEC.md §2).
///
/// Deliberately NOT carried over:
///   - the v1 demo routes (/demoHome, /demoUsers, /demoPosts/:id, /demoSettings,
///     /demoCategories) — template scaffolding
///   - /youtubeVideo — YouTube ingest was dropped on 2026-09-23 (OQ-06)
abstract final class Routes {
  static const String root = '/';
  static const String login = '/login';
  static const String transcriptionSummary = '/transcriptionSummary';
  static const String recordAudio = '/recordAudio';
  static const String uploadFile = '/uploadFile';
  static const String audioProcessing = '/audioProcessing';
  static const String settings = '/settings';
  static const String glossary = '/settings/glossary';
  /// Deep links (universal / app links + `oneai://` scheme): a shared note and
  /// one of the user's own notes. Same paths as Firebase Hosting rewrites.
  static const String sharedNote = '/s';
  static const String ownNote = '/n/:minuteId';
}

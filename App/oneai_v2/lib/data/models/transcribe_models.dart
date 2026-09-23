import 'package:one_ai/data/firebase/json_read.dart';
import 'package:one_ai/data/models/minute_models.dart';

class StartTranscriptionResult {
  const StartTranscriptionResult({required this.minuteId, required this.status, required this.duplicate});
  factory StartTranscriptionResult.fromJson(Map<String, dynamic> j) => StartTranscriptionResult(
        minuteId: readRequiredString(j, 'minuteId'),
        status: MinuteStatus.from(j, 'status'),
        duplicate: readBool(j, 'duplicate'),
      );
  final String minuteId;
  final MinuteStatus status;
  /// True when this requestId had already been processed — no second charge.
  final bool duplicate;
}

/// Options gathered on the record/upload screens and sent with startTranscription.
/// S11-08: shapes the summary's sections; mirrors `MinuteTemplate` server-side.
enum MinuteTemplate {
  auto, standup, oneOnOne, interview, lecture, brainstorm;

  String get wire => switch (this) { MinuteTemplate.oneOnOne => 'one_on_one', _ => name };
  static MinuteTemplate fromWire(String? s) => MinuteTemplate.values.firstWhere((t) => t.wire == s, orElse: () => MinuteTemplate.auto);
}

class TranscriptionOptions {
  const TranscriptionOptions({
    required this.summaryLanguage,
    this.audioLanguage = 'auto',
    this.keywords = const [],
    this.description,
    this.template = MinuteTemplate.auto,
    this.durationSeconds,
  });
  final String summaryLanguage;
  /// ISO-639-3 ("vie") or "auto".
  final String audioLanguage;
  final List<String> keywords;
  final String? description;
  final MinuteTemplate template;
  /// Client's best guess; the server measures the real one.
  final double? durationSeconds;
}

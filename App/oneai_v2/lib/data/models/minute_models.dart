// Mirrors functions-v2/src/minutes/types.ts. Decoded with the tolerant
// readers so an int-vs-double or a new enum value never crashes the app.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:one_ai/data/firebase/json_read.dart';
import 'package:one_ai/data/models/transcribe_models.dart';

enum SourceType {
  audio,
  pdf,
  unknown;

  static const _byName = {'audio': SourceType.audio, 'pdf': SourceType.pdf};
  static SourceType from(Map<String, dynamic> j, String k) =>
      readEnum(j, k, _byName, SourceType.unknown);
}

/// uploading → queued → transcribing → summarizing → ready | failed | cancelled
enum MinuteStatus {
  uploading,
  queued,
  transcribing,
  summarizing,
  ready,
  failed,
  cancelled,
  unknown;

  static const _byName = {
    'uploading': MinuteStatus.uploading,
    'queued': MinuteStatus.queued,
    'transcribing': MinuteStatus.transcribing,
    'summarizing': MinuteStatus.summarizing,
    'ready': MinuteStatus.ready,
    'failed': MinuteStatus.failed,
    'cancelled': MinuteStatus.cancelled,
  };
  static MinuteStatus from(Map<String, dynamic> j, String k) =>
      readEnum(j, k, _byName, MinuteStatus.unknown);

  bool get isProcessing =>
      this == MinuteStatus.queued ||
      this == MinuteStatus.transcribing ||
      this == MinuteStatus.summarizing;
  bool get isTerminal =>
      this == MinuteStatus.ready ||
      this == MinuteStatus.failed ||
      this == MinuteStatus.cancelled;
}

class MinuteSummary {
  const MinuteSummary({
    required this.id,
    required this.title,
    required this.iconEmoji,
    required this.sourceType,
    required this.contentKind,
    required this.status,
    required this.durationSeconds,
    required this.tagIds,
    required this.createdAt,
    required this.updatedAt,
    this.pinned = false,
    this.pinnedAt,
    this.transcriptPreview,
  });

  factory MinuteSummary.fromJson(Map<String, dynamic> j) => MinuteSummary(
        id: readRequiredString(j, 'id'),
        title: readString(j, 'title') ?? 'Untitled',
        iconEmoji: readString(j, 'iconEmoji'),
        sourceType: SourceType.from(j, 'sourceType'),
        contentKind: readString(j, 'contentKind'),
        status: MinuteStatus.from(j, 'status'),
        durationSeconds: readDouble(j, 'durationSeconds'),
        tagIds: readStringList(j, 'tagIds'),
        createdAt: readDateTime(j, 'createdAt') ?? DateTime.fromMillisecondsSinceEpoch(0),
        updatedAt: readDateTime(j, 'updatedAt') ?? DateTime.fromMillisecondsSinceEpoch(0),
        pinned: readBool(j, 'pinned'),
        pinnedAt: readDateTime(j, 'pinnedAt'),
      );

  /// From a live Firestore document (snapshots()). Dates are Timestamps
  /// here, not ISO strings; everything else matches the callable shape.
  factory MinuteSummary.fromFirestore(String id, Map<String, dynamic> d) {
    DateTime ts(String k) {
      final v = d[k];
      if (v is Timestamp) return v.toDate();
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
    final pinnedAtRaw = d['pinnedAt'];
    return MinuteSummary(
      id: id,
      title: readString(d, 'title') ?? 'Untitled',
      iconEmoji: readString(d, 'iconEmoji'),
      sourceType: SourceType.from(d, 'sourceType'),
      contentKind: readString(d, 'contentKind'),
      status: MinuteStatus.from(d, 'status'),
      durationSeconds: readDouble(d, 'durationSeconds'),
      tagIds: readStringList(d, 'tagIds'),
      createdAt: ts('createdAt'),
      updatedAt: ts('updatedAt'),
      pinned: readBool(d, 'pinned'),
      pinnedAt: pinnedAtRaw is Timestamp ? pinnedAtRaw.toDate() : null,
      // Server-written excerpt of the transcript; only the live stream has it.
      transcriptPreview: readString(d, 'transcriptPreview'),
    );
  }

  final String id;
  final String title;
  final String? iconEmoji;
  final SourceType sourceType;
  final String? contentKind;
  final MinuteStatus status;
  final double? durationSeconds;
  final List<String> tagIds;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool pinned;
  final DateTime? pinnedAt;
  final String? transcriptPreview;
}

class SummarySection {
  const SummarySection({required this.title, required this.bullets});
  factory SummarySection.fromJson(Map<String, dynamic> j) =>
      SummarySection(title: readString(j, 'title') ?? '', bullets: readStringList(j, 'bullets'));
  final String title;
  final List<String> bullets;
}

class Summary {
  const Summary({required this.title, required this.text, required this.icon, required this.sections});
  factory Summary.fromJson(Map<String, dynamic> j) => Summary(
        title: readString(j, 'title') ?? '',
        text: readString(j, 'text') ?? '',
        icon: readString(j, 'icon'),
        sections: readObjectList(j, 'sections').map(SummarySection.fromJson).toList(),
      );
  final String title;
  final String text;
  final String? icon;
  final List<SummarySection> sections;
}

class TranscriptSegment {
  const TranscriptSegment({
    required this.startSeconds,
    required this.endSeconds,
    required this.text,
    required this.speakerId,
    required this.speakerLabel,
  });
  factory TranscriptSegment.fromJson(Map<String, dynamic> j) => TranscriptSegment(
        startSeconds: readDouble(j, 'startSeconds') ?? 0,
        endSeconds: readDouble(j, 'endSeconds') ?? 0,
        text: readString(j, 'text') ?? '',
        speakerId: readString(j, 'speakerId') ?? 'speaker_0',
        speakerLabel: readString(j, 'speakerLabel') ?? 'Speaker 1',
      );
  final double startSeconds;
  final double endSeconds;
  final String text;
  final String speakerId;
  final String speakerLabel;
}

class Transcript {
  const Transcript({
    required this.durationSeconds,
    required this.languageCode,
    required this.languageProbability,
    required this.text,
    required this.segments,
  });
  factory Transcript.fromJson(Map<String, dynamic> j) => Transcript(
        durationSeconds: readDouble(j, 'durationSeconds') ?? 0,
        languageCode: readString(j, 'languageCode'),
        languageProbability: readDouble(j, 'languageProbability'),
        text: readString(j, 'text') ?? '',
        segments: readObjectList(j, 'segments').map(TranscriptSegment.fromJson).toList(),
      );
  final double durationSeconds;
  final String? languageCode;
  final double? languageProbability;
  final String text;
  final List<TranscriptSegment> segments;
}

class Speaker {
  const Speaker({required this.id, required this.label});
  factory Speaker.fromJson(Map<String, dynamic> j) =>
      Speaker(id: readString(j, 'id') ?? '', label: readString(j, 'label') ?? '');
  final String id;
  final String label;
}

/// An event the summariser extracted; regenerate via `generateCalendarEvents`.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.datetime,
    required this.participants,
    required this.rawText,
  });
  factory CalendarEvent.fromJson(Map<String, dynamic> j) => CalendarEvent(
        id: readString(j, 'id') ?? '',
        title: readString(j, 'title') ?? '',
        description: readString(j, 'description') ?? '',
        datetime: readString(j, 'datetime') ?? '',
        participants: readStringList(j, 'participants'),
        rawText: readString(j, 'rawText') ?? '',
      );
  final String id;
  final String title;
  final String description;

  /// ISO-8601 when the model could resolve it, otherwise the wording as spoken.
  final String datetime;
  final List<String> participants;
  final String rawText;

  /// Parsed [datetime], or null when it is free text ("next Friday").
  DateTime? get resolvedAt => DateTime.tryParse(datetime);
}

/// `artifacts/{kind}` docs the server may hold for a note.
enum ArtifactKind {
  shortQuestions,
  quiz,
  flashcards,
  mindmap,
  speakers,
  calendarEvents,
  actionItems,
  keyTerms,
  chapters;

  static ArtifactKind? fromName(String name) {
    for (final k in values) {
      if (k.name == name) return k;
    }
    return null;
  }
}

/// `none` before upload, `available` while the bytes exist, `expired` once
/// retention removed them (transcript and summary stay).
enum SourceState {
  none,
  available,
  expired;

  static SourceState from(Map<String, dynamic> j, String k) => readEnum(
        j,
        k,
        const {'none': SourceState.none, 'available': SourceState.available, 'expired': SourceState.expired},
        SourceState.none,
      );
}

/// Per-speaker talk time, computed server-side from the transcript.
class TalkTime {
  const TalkTime({required this.speakerId, required this.label, required this.seconds, required this.share, required this.turns});
  factory TalkTime.fromJson(Map<String, dynamic> j) => TalkTime(
        speakerId: readString(j, 'speakerId') ?? '',
        label: readString(j, 'label') ?? '',
        seconds: readDouble(j, 'seconds') ?? 0,
        share: readDouble(j, 'share') ?? 0,
        turns: readInt(j, 'turns') ?? 0,
      );
  final String speakerId;
  final String label;
  final double seconds;
  /// 0..1
  final double share;
  final int turns;
}

class MinuteFailure {
  const MinuteFailure({required this.code, required this.message});
  factory MinuteFailure.fromJson(Map<String, dynamic> j) =>
      MinuteFailure(code: readString(j, 'code') ?? 'unknown', message: readString(j, 'message') ?? '');
  final String code;
  final String message;
}

/// What the processing screen watches: status + failure, straight from the
/// Firestore doc, updated by the worker as it moves through the pipeline.
class MinuteProgress {
  const MinuteProgress({required this.id, required this.status, required this.failure, required this.title});
  factory MinuteProgress.fromFirestore(String id, Map<String, dynamic> d) {
    final f = readObject(d, 'failure');
    return MinuteProgress(
      id: id,
      status: MinuteStatus.from(d, 'status'),
      failure: f == null ? null : MinuteFailure.fromJson(f),
      title: readString(d, 'title') ?? 'Untitled',
    );
  }
  final String id;
  final MinuteStatus status;
  final MinuteFailure? failure;
  final String title;
}

/// S11-05 read-only share link.
class ShareInfo {
  const ShareInfo({required this.url, required this.includeTranscript, required this.createdAt, required this.views});
  factory ShareInfo.fromJson(Map<String, dynamic> j) => ShareInfo(
        url: readString(j, 'url') ?? '',
        includeTranscript: readBool(j, 'includeTranscript'),
        createdAt: readDateTime(j, 'createdAt') ?? DateTime.fromMillisecondsSinceEpoch(0),
        views: readInt(j, 'views') ?? 0,
      );
  final String url;
  final bool includeTranscript;
  final DateTime createdAt;
  final int views;

  /// Decided 24/09: what we hand to people is the PDF. The HTML page behind
  /// [url] stays as the fallback (and carries a Download PDF button).
  String get pdfUrl => '$url${url.contains('?') ? '&' : '?'}format=pdf';
}

ShareInfo? _shareOf(Map<String, dynamic> j) {
  final s = readObject(j, 'share');
  return s == null ? null : ShareInfo.fromJson(s);
}

class MinuteDetail {
  const MinuteDetail({
    required this.summaryInfo,
    required this.summary,
    required this.transcript,
    required this.sourcePath,
    required this.speakers,
    required this.failure,
    required this.description,
    required this.keywords,
    required this.summaryLanguage,
    this.calendarEvents = const [],
    this.availableArtifacts = const {},
    this.sourceState = SourceState.none,
    this.sourceExpiresAt,
    this.talkTime = const [],
    this.template = MinuteTemplate.auto,
    this.share,
  });

  factory MinuteDetail.fromJson(Map<String, dynamic> j) {
    final s = readObject(j, 'summary');
    final t = readObject(j, 'transcript');
    final f = readObject(j, 'failure');
    return MinuteDetail(
      summaryInfo: MinuteSummary.fromJson(j),
      summary: s == null ? null : Summary.fromJson(s),
      transcript: t == null ? null : Transcript.fromJson(t),
      sourcePath: readString(j, 'sourcePath'),
      speakers: readObjectList(j, 'speakers').map(Speaker.fromJson).toList(),
      failure: f == null ? null : MinuteFailure.fromJson(f),
      description: readString(j, 'description'),
      keywords: readStringList(j, 'keywords'),
      summaryLanguage: readString(j, 'summaryLanguage'),
      template: MinuteTemplate.fromWire(readString(j, 'template')),
      share: _shareOf(j),
      calendarEvents: readObjectList(j, 'calendarEvents').map(CalendarEvent.fromJson).toList(),
      availableArtifacts: readStringList(j, 'availableArtifacts').map(ArtifactKind.fromName).nonNulls.toSet(),
      sourceState: j.containsKey('sourceState') ? SourceState.from(j, 'sourceState') : (readString(j, 'sourcePath') == null ? SourceState.none : SourceState.available),
      sourceExpiresAt: readDateTime(j, 'sourceExpiresAt'),
      talkTime: readObjectList(j, 'talkTime').map(TalkTime.fromJson).toList(),
    );
  }

  /// The list-row fields (id, title, status, …).
  final MinuteSummary summaryInfo;
  final Summary? summary;
  final Transcript? transcript;
  /// Storage path of the source; resolve a download URL with firebase_storage.
  final String? sourcePath;
  final List<Speaker> speakers;
  final MinuteFailure? failure;
  final String? description;
  final List<String> keywords;
  final String? summaryLanguage;
  /// S11-08 template the summary was written with.
  final MinuteTemplate template;
  /// Live read-only share link (S11-05), or null.
  final ShareInfo? share;

  /// Extracted at summarise time. Empty when nothing was scheduled.
  final List<CalendarEvent> calendarEvents;

  /// Which artifacts already exist server-side — show those tabs as ready
  /// without a generate call.
  final Set<ArtifactKind> availableArtifacts;

  bool hasArtifact(ArtifactKind k) => availableArtifacts.contains(k);

  /// Whether the original audio/PDF can still be played or downloaded.
  final SourceState sourceState;

  /// When retention will remove the source bytes; null = kept indefinitely.
  final DateTime? sourceExpiresAt;
  bool get canPlaySource => sourceState == SourceState.available && sourcePath != null;

  /// Who spoke how much. Empty for PDFs.
  final List<TalkTime> talkTime;

  String get id => summaryInfo.id;
  MinuteStatus get status => summaryInfo.status;

  /// Display label for a segment's speaker, honouring renames.
  String speakerLabelFor(String speakerId) {
    for (final s in speakers) {
      if (s.id == speakerId) return s.label;
    }
    return speakerId;
  }
}

class CreateMinuteResult {
  const CreateMinuteResult({required this.minuteId, required this.uploadPath, required this.contentType, required this.maxSizeBytes});
  factory CreateMinuteResult.fromJson(Map<String, dynamic> j) {
    final u = readObject(j, 'upload') ?? const <String, dynamic>{};
    return CreateMinuteResult(
      minuteId: readRequiredString(j, 'minuteId'),
      uploadPath: readRequiredString(u, 'path'),
      contentType: readString(u, 'contentType') ?? 'application/octet-stream',
      maxSizeBytes: readInt(u, 'maxSizeBytes') ?? 300 * 1024 * 1024,
    );
  }
  final String minuteId;
  final String uploadPath;
  final String contentType;
  final int maxSizeBytes;
}

class MinutePage {
  const MinutePage({required this.items, required this.nextCursor});
  factory MinutePage.fromJson(Map<String, dynamic> j) => MinutePage(
        items: readObjectList(j, 'items').map(MinuteSummary.fromJson).toList(),
        nextCursor: readString(j, 'nextCursor'),
      );
  final List<MinuteSummary> items;
  /// Opaque. `null` means last page.
  final String? nextCursor;
}

enum ListSort { createdAtDesc, titleAsc }

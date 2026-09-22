// Mirrors functions-v2/src/minutes/types.ts. Decoded with the tolerant
// readers so an int-vs-double or a new enum value never crashes the app.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:one_ai/data/firebase/json_read.dart';

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
      );

  /// From a live Firestore document (snapshots()). Dates are Timestamps
  /// here, not ISO strings; everything else matches the callable shape.
  factory MinuteSummary.fromFirestore(String id, Map<String, dynamic> d) {
    DateTime ts(String k) {
      final v = d[k];
      if (v is Timestamp) return v.toDate();
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
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

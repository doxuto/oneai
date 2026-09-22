import 'dart:io';
import 'dart:ui';

import 'package:codebase_ai/data/services/pdf_service.dart';
import 'package:codebase_ai/domain/models/meeting_minute_model.dart';
import 'package:codebase_ai/domain/models/transcript_message_model.dart';
import 'package:codebase_ai/utils/result.dart';
import 'package:logging/logging.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Repository for sharing content
abstract class ShareRepository {
  /// Share meeting minutes as PDF
  Future<Result<void>> shareNotesAsPdf(MeetingMinute meetingMinute, {Rect? sharePositionOrigin});

  /// Share meeting minutes as text
  Future<Result<void>> shareNotesAsText(MeetingMinute meetingMinute, {Rect? sharePositionOrigin});

  /// Share transcript as PDF
  Future<Result<void>> shareTranscriptAsPdf(
    String title,
    String date,
    String duration,
    Transcript transcript, {
    Rect? sharePositionOrigin,
  });

  /// Share transcript as text
  Future<Result<void>> shareTranscriptAsText(
    String title,
    String date,
    String duration,
    Transcript transcript, {
    Rect? sharePositionOrigin,
  });

  /// Share audio file
  Future<Result<void>> shareAudioFile(String audioPath, {Rect? sharePositionOrigin});
}

/// Implementation of the ShareRepository
class ShareRepositoryImpl implements ShareRepository {
  final PdfService _pdfService;
  final _log = Logger('ShareRepositoryImpl');

  /// Constructor
  ShareRepositoryImpl({required PdfService pdfService}) : _pdfService = pdfService;

  @override
  Future<Result<void>> shareNotesAsPdf(MeetingMinute meetingMinute, {Rect? sharePositionOrigin}) async =>
      _pdfService.shareNotesAsPdf(meetingMinute, sharePositionOrigin: sharePositionOrigin);

  @override
  Future<Result<void>> shareNotesAsText(MeetingMinute meetingMinute, {Rect? sharePositionOrigin}) async {
    try {
      final String textContent = _generateMeetingMinuteText(meetingMinute);
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/${meetingMinute.title.replaceAll(' ', '_')}_notes.txt';

      final file = File(filePath);
      await file.writeAsString(textContent);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          title: meetingMinute.title,
          subject: meetingMinute.title,
          sharePositionOrigin: sharePositionOrigin,
        ),
      );

      _log.info('Text notes shared successfully');
      return const Result.ok(null);
    } on Exception catch (e) {
      _log.severe('Error sharing text notes: $e');
      return Result.error(e);
    }
  }

  @override
  Future<Result<void>> shareTranscriptAsPdf(
    String title,
    String date,
    String duration,
    Transcript transcript, {
    Rect? sharePositionOrigin,
  }) async =>
      _pdfService.shareTranscriptAsPdf(title, date, duration, transcript, sharePositionOrigin: sharePositionOrigin);

  @override
  Future<Result<void>> shareTranscriptAsText(
    String title,
    String date,
    String duration,
    Transcript transcript, {
    Rect? sharePositionOrigin,
  }) async {
    try {
      final String textContent = _generateTranscriptText(title, date, duration, transcript);
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/${title.replaceAll(' ', '_')}_transcript.txt';

      final file = File(filePath);
      await file.writeAsString(textContent);

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(filePath)],
          title: '$title - Transcript',
          subject: '$title - Transcript',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );

      _log.info('Transcript text shared successfully');
      return const Result.ok(null);
    } on Exception catch (e) {
      _log.severe('Error sharing transcript text: $e');
      return Result.error(e);
    }
  }

  @override
  Future<Result<void>> shareAudioFile(String audioPath, {Rect? sharePositionOrigin}) async {
    try {
      final file = File(audioPath);
      if (!await file.exists()) {
        return Result.error(FileSystemException('Audio file not found', audioPath));
      }

      final fileName = file.uri.pathSegments.last;

      _log.fine('Audio file shared before: $fileName');

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(audioPath)],
          title: fileName,
          subject: fileName,
          sharePositionOrigin: sharePositionOrigin,
        ),
      );

      _log.info('Audio file shared successfully: $fileName');
      return const Result.ok(null);
    } on Exception catch (e) {
      _log.severe('Error sharing audio file: $e');
      return Result.error(e);
    }
  }

  /// Generate text content for meeting minutes
  String _generateMeetingMinuteText(MeetingMinute meetingMinute) {
    final StringBuffer buffer =
        StringBuffer()
          // Add title and meeting info
          ..writeln(meetingMinute.title.toUpperCase())
          ..writeln('${meetingMinute.date} - ${meetingMinute.duration}')
          ..writeln();

    // Add sections
    for (final section in meetingMinute.sections) {
      final timeRange = section.timeRange.isNotEmpty ? '(${section.timeRange})' : '';
      buffer.writeln('${section.title}$timeRange');

      // Add bullet points
      section.bulletPoints.forEach(buffer.writeln);

      buffer.writeln();
    }

    return buffer.toString();
  }

  /// Generate text content for transcript
  String _generateTranscriptText(String title, String date, String duration, Transcript transcript) {
    final StringBuffer buffer =
        StringBuffer()
          // Add title and meeting info
          ..writeln('$title - TRANSCRIPT')
          ..writeln('$date - $duration')
          ..writeln();

    // Add transcript messages
    for (final message in transcript.messages) {
      buffer
        ..writeln('${message.speakerName} (${message.timestamp}):')
        ..writeln(message.message)
        ..writeln();
    }

    return buffer.toString();
  }
}

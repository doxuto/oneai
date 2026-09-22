import 'package:codebase_ai/domain/models/meeting_minute_model.dart';
import 'package:codebase_ai/domain/models/minute_model.dart';
import 'package:codebase_ai/domain/models/transcript_message_model.dart';
import 'package:intl/intl.dart';

String formatDateTimeToString(DateTime? dateTime) {
  if (dateTime == null) {
    return '';
  }
  return DateFormat('M/d/y, HH:mm').format(dateTime);
}

String _formatDuration(String duration) {
  // Accepts 'mm:ss' or 'hh:mm:ss' and returns 'X min, Y sec'
  final parts = duration.split(':').map(int.tryParse).whereType<int>().toList();
  int minutes = 0;
  int seconds = 0;
  if (parts.length == 2) {
    minutes = parts[0];
    seconds = parts[1];
  } else if (parts.length == 3) {
    minutes = parts[0] * 60 + parts[1];
    seconds = parts[2];
  }
  return '$minutes min, $seconds sec';
}

MeetingMinute minuteToMeetingMinute(Minute minute) {
  final summarySections = minute.summary?.sections ?? [];
  return MeetingMinute(
    title: minute.title ?? '',
    date: formatDateTimeToString(minute.createdAt),
    duration: _formatDuration(minute.transcription?.duration ?? ''),
    sections: [
      for (final section in summarySections)
        MeetingMinuteSection(
          timeRange: section.timeRange ?? '',
          title: section.title ?? '',
          bulletPoints: section.bullets ?? [],
        ),
    ],
  );
}

Transcript minuteToTranscript(Minute minute) {
  final sections = minute.transcription?.sections ?? [];
  final speakersMap = minute.speakers ?? {};

  int? extractSpeakerIdNumber(String? speakerId) {
    if (speakerId == null) {
      return null;
    }
    final match = RegExp(r'\d+').allMatches(speakerId);
    if (match.isNotEmpty) {
      return int.tryParse(match.last.group(0) ?? '');
    }
    return null;
  }

  String? extractSpeakerName(String? speakerId, Map<String, String> speakersMap, String? defaultName) {
    if (speakerId == null) {
      return defaultName;
    }
    final name = speakersMap[speakerId];
    if (name != null && name.isNotEmpty && name != speakerId) {
      return name;
    }
    return defaultName;
  }

  return Transcript(
    messages: [
      for (final section in sections)
        TranscriptMessage(
          speakerName: extractSpeakerName(section.speakerId, speakersMap, section.speaker) ?? '',
          speakerId: (extractSpeakerIdNumber(section.speakerId) ?? 0) + 1,
          timestamp: section.timeRange ?? '',
          message: section.title ?? '',
          speakerIdRaw: section.speakerId ?? '',
        ),
    ],
  );
}

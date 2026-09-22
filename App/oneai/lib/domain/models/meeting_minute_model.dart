import 'package:freezed_annotation/freezed_annotation.dart';

part 'meeting_minute_model.freezed.dart';
part 'meeting_minute_model.g.dart';

/// Model representing a meeting minute section with title, timestamp, and bullet points
@freezed
sealed class MeetingMinuteSection with _$MeetingMinuteSection {
  const factory MeetingMinuteSection({
    required String timeRange,
    required String title,
    required List<String> bulletPoints,
  }) = _MeetingMinuteSection;

  factory MeetingMinuteSection.fromJson(Map<String, dynamic> json) => _$MeetingMinuteSectionFromJson(json);
}

/// Model representing a full meeting minute with metadata and sections
@freezed
sealed class MeetingMinute with _$MeetingMinute {
  const factory MeetingMinute({
    required String title,
    required String date,
    required String duration,
    required List<MeetingMinuteSection> sections,
  }) = _MeetingMinute;

  factory MeetingMinute.fromJson(Map<String, dynamic> json) => _$MeetingMinuteFromJson(json);
}

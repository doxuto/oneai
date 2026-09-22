import 'package:codebase_ai/data/services/model/oneai/summary_dto.dart';
import 'package:codebase_ai/data/services/model/oneai/transcription_details_dto.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'minute_dto.freezed.dart';
part 'minute_dto.g.dart';

class FirestoreDateTimeConverter implements JsonConverter<DateTime?, Object?> {
  const FirestoreDateTimeConverter();

  @override
  DateTime? fromJson(Object? json) {
    if (json == null) return null;
    if (json is DateTime) return json;
    if (json is Map && json.containsKey('_seconds')) {
      final secondsRaw = json['_seconds'];
      final nanosecondsRaw = json['_nanoseconds'];
      final seconds = secondsRaw is int ? secondsRaw : (secondsRaw is double ? secondsRaw.toInt() : null);
      final nanoseconds = nanosecondsRaw is int
          ? nanosecondsRaw
          : (nanosecondsRaw is double ? nanosecondsRaw.toInt() : 0);
      if (seconds != null) {
        return DateTime.fromMillisecondsSinceEpoch(
          Duration(seconds: seconds, microseconds: nanoseconds ~/ 1000).inMilliseconds,
        );
      }
    }
    return null;
  }

  @override
  Object? toJson(DateTime? dateTime) {
    if (dateTime == null) return null;
    final ms = dateTime.millisecondsSinceEpoch;
    return {'_seconds': ms ~/ 1000, '_nanoseconds': (ms % 1000) * 1000000};
  }
}

@freezed
abstract class MinuteDto with _$MinuteDto {
  const factory MinuteDto({
    required String minuteId,
    SummaryDto? summary,
    String? summaryLanguage,
    String? keywords,
    TranscriptionDetailsDto? transcription,
    String? title,
    String? descriptionAudio,
    String? gcsUri,
    @FirestoreDateTimeConverter() DateTime? createdAt,
    List<String>? tags,
    String? type,
    String? iconAsset,
    List<String>? shortQuestions,
    String? duration,
    Map<String, String>? speakers,
  }) = _MinuteDto;

  factory MinuteDto.fromJson(Map<String, dynamic> json) => _$MinuteDtoFromJson(json);
}

@freezed
abstract class MinuteResponseDto with _$MinuteResponseDto {
  const factory MinuteResponseDto({required int total, required List<MinuteDto> data, String? nextPageCursor}) =
      _MinuteResponseDto;

  factory MinuteResponseDto.fromJson(Map<String, dynamic> json) => _$MinuteResponseDtoFromJson(json);
}

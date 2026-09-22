import 'package:freezed_annotation/freezed_annotation.dart';

part 'transcription_details_dto.freezed.dart';
part 'transcription_details_dto.g.dart';

@freezed
sealed class TranscriptionDetailsDto with _$TranscriptionDetailsDto {
  const factory TranscriptionDetailsDto({
    String? duration,
    String? language_code,
    String? transcript,
    double? language_probability,
    List<TranscriptionSectionDto>? sections,
  }) = _TranscriptionDetailsDto;

  factory TranscriptionDetailsDto.fromJson(Map<String, dynamic> json) => _$TranscriptionDetailsDtoFromJson(json);
}

@freezed
sealed class TranscriptionSectionDto with _$TranscriptionSectionDto {
  const factory TranscriptionSectionDto({
    String? timeRange,
    String? title,
    String? speaker,
    @JsonKey(name: 'speaker_id') String? speakerId,
  }) = _TranscriptionSectionDto;

  factory TranscriptionSectionDto.fromJson(Map<String, dynamic> json) => _$TranscriptionSectionDtoFromJson(json);
}

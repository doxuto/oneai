import 'package:codebase_ai/data/services/model/oneai/transcription_details_dto.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'transcription_dto.freezed.dart';
part 'transcription_dto.g.dart';

@freezed
abstract class TranscriptionDto with _$TranscriptionDto {
  const factory TranscriptionDto({
    String? minuteId,
    TranscriptionDetailsDto? transcription,
    String? description,
    String? keywords,
    String? title,
  }) = _TranscriptionDto;

  factory TranscriptionDto.fromJson(Map<String, dynamic> json) => _$TranscriptionDtoFromJson(json);
}

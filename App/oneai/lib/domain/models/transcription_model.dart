import 'package:freezed_annotation/freezed_annotation.dart';

part 'transcription_model.freezed.dart';
part 'transcription_model.g.dart';

@freezed
sealed class Transcription with _$Transcription {
  const factory Transcription({
    String? minuteId,
    TranscriptionDetails? transcription,
    String? description,
    String? keywords,
    String? title,
  }) = _Transcription;

  factory Transcription.fromJson(Map<String, dynamic> json) => _$TranscriptionFromJson(json);
}

@freezed
sealed class TranscriptionDetails with _$TranscriptionDetails {
  const factory TranscriptionDetails({
    String? duration,
    @JsonKey(name: 'language_code') String? languageCode,
    String? transcript,
    @JsonKey(name: 'language_probability') double? languageProbability,
    List<TranscriptionSection>? sections,
  }) = _TranscriptionDetails;

  factory TranscriptionDetails.fromJson(Map<String, dynamic> json) => _$TranscriptionDetailsFromJson(json);
}

@freezed
sealed class TranscriptionSection with _$TranscriptionSection {
  const factory TranscriptionSection({String? timeRange, String? title, String? speaker, String? speakerId}) =
      _TranscriptionSection;

  factory TranscriptionSection.fromJson(Map<String, dynamic> json) => _$TranscriptionSectionFromJson(json);
}

import 'package:codebase_ai/domain/models/summary_model.dart';
import 'package:codebase_ai/domain/models/transcription_model.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'minute_model.freezed.dart';
part 'minute_model.g.dart';

@freezed
sealed class Minute with _$Minute {
  const factory Minute({
    required String id,
    String? title,
    String? summaryLanguage,
    String? keywords,
    TranscriptionDetails? transcription,
    String? descriptionAudio,
    String? gcsUri,
    DateTime? createdAt,
    List<String>? tags,
    String? type,
    String? iconAsset,
    List<String>? shortQuestions,
    Summary? summary,
    String? duration,
    Map<String, String>? speakers,
  }) = _Minute;

  factory Minute.fromJson(Map<String, dynamic> json) => _$MinuteFromJson(json);
}

@freezed
abstract class MinuteResponse with _$MinuteResponse {
  const factory MinuteResponse({required int total, required List<Minute> data, String? nextPageCursor}) =
      _MinuteResponse;

  factory MinuteResponse.fromJson(Map<String, dynamic> json) => _$MinuteResponseFromJson(json);
}

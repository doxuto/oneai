import 'package:freezed_annotation/freezed_annotation.dart';

part 'transcript_message_model.freezed.dart';
part 'transcript_message_model.g.dart';

/// Model representing a single transcript message from a speaker
@freezed
sealed class TranscriptMessage with _$TranscriptMessage {
  const factory TranscriptMessage({
    required int speakerId,
    required String speakerName,
    required String timestamp,
    required String message,
    required String speakerIdRaw,
  }) = _TranscriptMessage;

  factory TranscriptMessage.fromJson(Map<String, dynamic> json) => _$TranscriptMessageFromJson(json);
}

/// Model representing a full transcript with all messages
@freezed
sealed class Transcript with _$Transcript {
  const factory Transcript({required List<TranscriptMessage> messages}) = _Transcript;

  factory Transcript.fromJson(Map<String, dynamic> json) => _$TranscriptFromJson(json);
}

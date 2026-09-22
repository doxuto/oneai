import 'package:freezed_annotation/freezed_annotation.dart';

part 'chat_dto.freezed.dart';

part 'chat_dto.g.dart';

@freezed
abstract class ChatDto with _$ChatDto {
  const factory ChatDto({required String question, required String answer, String? minuteId}) = _ChatDto;

  factory ChatDto.fromJson(Map<String, dynamic> json) => _$ChatDtoFromJson(json);
}

import 'package:freezed_annotation/freezed_annotation.dart';

part 'question_dto.freezed.dart';

part 'question_dto.g.dart';

@freezed
abstract class QuestionDto with _$QuestionDto {
  const factory QuestionDto({@JsonKey(name: 'short_questions') @Default([]) List<String> shortQuestions}) =
      _QuestionDto;

  factory QuestionDto.fromJson(Map<String, dynamic> json) => _$QuestionDtoFromJson(json);
}

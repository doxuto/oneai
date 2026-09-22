import 'package:codebase_ai/data/services/model/oneai/minute_dto.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'user_dto.freezed.dart';
part 'user_dto.g.dart';

@freezed
sealed class OneAiUserDto with _$OneAiUserDto {
  const factory OneAiUserDto({
    required String uid,
    required String? email,
    required String? displayName,
    required String? photoURL,
    required String role,
    required String plan,
    required int credit,
    @FirestoreDateTimeConverter() DateTime? createdAt,
  }) = _OneAiUserDto;

  factory OneAiUserDto.fromJson(Map<String, dynamic> json) => _$OneAiUserDtoFromJson(json);
}

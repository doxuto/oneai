import 'package:freezed_annotation/freezed_annotation.dart';

part 'oneai_user_model.freezed.dart';
part 'oneai_user_model.g.dart';

@freezed
sealed class OneAiUser with _$OneAiUser {
  const factory OneAiUser({
    required String uid,
    required String? email,
    required String role,
    required String plan,
    required int credit,
  }) = _OneAiUser;

  factory OneAiUser.fromJson(Map<String, dynamic> json) => _$OneAiUserFromJson(json);
}

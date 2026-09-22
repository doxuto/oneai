import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_user_model.freezed.dart';

part 'auth_user_model.g.dart';

/// Authentication user model that represents a authenticated user
@freezed
sealed class AuthUser with _$AuthUser {
  /// Creates a new auth user
  const factory AuthUser({
    required String uid,
    required String? displayName,
    required String? email,
    required String? photoURL,
    required bool isAnonymous,
    @Default(false) bool isEmailVerified,
  }) = _AuthUser;

  /// Creates an AuthUser from Firebase User
  factory AuthUser.fromJson(Map<String, dynamic> json) => _$AuthUserFromJson(json);
}

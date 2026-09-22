import 'package:codebase_ai/domain/models/auth_user_model.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_state.freezed.dart';

/// States for the authentication bloc
@freezed
class AuthState with _$AuthState {
  /// Authentication initial/loading state
  const factory AuthState.initial() = InitialAuthState;

  /// Authentication process is in progress
  const factory AuthState.loading() = LoadingAuthState;

  /// User is authenticated
  const factory AuthState.authenticated(AuthUser user) = AuthenticatedAuthState;

  /// User is not authenticated
  const factory AuthState.unauthenticated() = UnauthenticatedAuthState;

  /// Authentication failed with an error
  const factory AuthState.error(String message) = ErrorAuthState;
}

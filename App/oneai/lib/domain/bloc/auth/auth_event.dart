import 'package:freezed_annotation/freezed_annotation.dart';

part 'auth_event.freezed.dart';

/// Events for the authentication bloc
@freezed
sealed class AuthEvent with _$AuthEvent {
  /// Initialize authentication and listen for auth state changes
  const factory AuthEvent.initialize() = InitializeEvent;

  /// Sign in with Google
  const factory AuthEvent.signInWithGoogle() = SignInWithGoogleEvent;

  /// Sign in with Apple
  const factory AuthEvent.signInWithApple() = SignInWithAppleEvent;

  /// Sign out the current user
  const factory AuthEvent.signOut() = SignOutEvent;
}

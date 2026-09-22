import 'package:codebase_ai/data/services/auth_service.dart';
import 'package:codebase_ai/domain/models/auth_user_model.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Interface for authentication repository
abstract class AuthRepository {
  /// Stream of auth user changes
  Stream<AuthUser?> get authStateChanges;

  /// Current authenticated user
  AuthUser? get currentUser;

  /// Sign in with Google
  Future<AuthUser?> signInWithGoogle();

  /// Sign in with Apple
  Future<AuthUser?> signInWithApple();

  /// Sign out current user
  Future<void> signOut();

  /// Delete current user account
  Future<void> deleteAccount();

  /// Check if user is authenticated
  bool get isAuthenticated;
}

/// Implementation of AuthRepository
class AuthRepositoryImpl implements AuthRepository {
  final AuthService _authService;

  /// Creates a new AuthRepositoryImpl with the given auth service
  AuthRepositoryImpl({required AuthService authService}) : _authService = authService;

  @override
  Stream<AuthUser?> get authStateChanges =>
      _authService.authStateChanges.map((user) => user != null ? _mapUserToAuthUser(user) : null);

  @override
  AuthUser? get currentUser {
    final user = _authService.currentUser;
    if (user == null) {
      return null;
    }
    return _mapUserToAuthUser(user);
  }

  @override
  Future<AuthUser?> signInWithGoogle() async {
    try {
      final credential = await _authService.signInWithGoogle();
      if (credential.user == null) {
        return null;
      }
      return _mapUserToAuthUser(credential.user!);
    } catch (e) {
      // Log error and return null
      return null;
    }
  }

  @override
  Future<AuthUser?> signInWithApple() async {
    try {
      final credential = await _authService.signInWithApple();
      if (credential.user == null) {
        return null;
      }
      return _mapUserToAuthUser(credential.user!);
    } catch (e) {
      // Log error and return null
      return null;
    }
  }

  @override
  Future<void> signOut() => _authService.signOut();

  @override
  bool get isAuthenticated => _authService.currentUser != null;

  @override
  Future<void> deleteAccount() => _authService.deleteAccount();

  /// Maps a Firebase User to our domain AuthUser model
  AuthUser _mapUserToAuthUser(User user) => AuthUser(
    uid: user.uid,
    displayName: user.displayName,
    email: user.email,
    photoURL: user.photoURL,
    isAnonymous: user.isAnonymous,
    isEmailVerified: user.emailVerified,
  );
}

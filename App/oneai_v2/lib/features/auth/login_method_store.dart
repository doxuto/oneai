import 'package:one_ai/features/auth/auth_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Remembers which provider the user last signed in with, for the
/// "(Previously signed in with …)" hint on the login page. Per-device cache,
/// nothing else — safe to lose.
abstract interface class LoginMethodStore {
  Future<AuthProviderKind?> read();
  Future<void> write(AuthProviderKind provider);
}

class PrefsLoginMethodStore implements LoginMethodStore {
  const PrefsLoginMethodStore();

  /// Same key as v1 so an in-place upgrade keeps the hint.
  static const key = 'LOGIN_METHOD';

  @override
  Future<AuthProviderKind?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AuthProviderKind.fromStorageKey(prefs.getString(key));
    } on Object catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(AuthProviderKind provider) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, provider.storageKey);
    } on Object catch (_) {
      // Cosmetic; never fail a sign-in over it.
    }
  }
}

class InMemoryLoginMethodStore implements LoginMethodStore {
  AuthProviderKind? value;
  @override
  Future<AuthProviderKind?> read() async => value;
  @override
  Future<void> write(AuthProviderKind provider) async => value = provider;
}

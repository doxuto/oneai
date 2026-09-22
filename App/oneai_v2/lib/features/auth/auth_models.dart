/// Provider-agnostic auth types. Nothing here imports firebase_auth, so the
/// controller and its tests stay free of platform channels.
enum AuthProviderKind {
  google('google', 'google.com'),
  apple('apple', 'apple.com');

  const AuthProviderKind(this.storageKey, this.firebaseProviderId);

  /// Value persisted for "Previously signed in with …". Same strings as v1
  /// (`LOGIN_METHOD` = `google` | `apple`) so an upgrade keeps the label.
  final String storageKey;

  /// `UserInfo.providerId` as reported by Firebase.
  final String firebaseProviderId;

  static AuthProviderKind? fromStorageKey(String? key) {
    for (final k in values) {
      if (k.storageKey == key) return k;
    }
    return null;
  }
}

/// What the app needs to know about the signed-in account. Mirrors
/// `users/{uid}` closely enough that the header can render before `getMe`
/// answers.
class AuthAccount {
  const AuthAccount({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    this.providers = const {},
  });

  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;

  /// Linked providers (Firebase provider ids) — used to pick which provider to
  /// re-authenticate with.
  final Set<String> providers;

  AuthProviderKind? get primaryProvider {
    for (final k in AuthProviderKind.values) {
      if (providers.contains(k.firebaseProviderId)) return k;
    }
    return null;
  }
}

/// Every way a sign-in can end other than success. Sealed so the login page's
/// switch is exhaustive; `cancelled` must be silent in the UI.
sealed class SignInFailure implements Exception {
  const SignInFailure(this.provider, [this.debugMessage]);
  final AuthProviderKind provider;
  final String? debugMessage;
}

/// The user dismissed the native sheet. Not an error — show nothing.
final class SignInCancelled extends SignInFailure {
  const SignInCancelled(super.provider);
}

/// No network / the identity provider was unreachable. Retryable.
final class SignInNetwork extends SignInFailure {
  const SignInNetwork(super.provider, [super.debugMessage]);
}

/// Misconfiguration (SHA-1 missing, Services ID wrong, entitlement absent).
/// Never the user's fault; surface a generic message and log the detail.
final class SignInConfiguration extends SignInFailure {
  const SignInConfiguration(super.provider, [super.debugMessage]);
}

/// The account exists with a different provider, or Firebase refused the
/// credential (`account-exists-with-different-credential`, `user-disabled`…).
final class SignInRejected extends SignInFailure {
  const SignInRejected(super.provider, this.code, [super.debugMessage]);
  final String code;
}

final class SignInUnknown extends SignInFailure {
  const SignInUnknown(super.provider, [super.debugMessage]);
}

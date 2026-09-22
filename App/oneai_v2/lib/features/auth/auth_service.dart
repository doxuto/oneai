import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:one_ai/features/auth/auth_models.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// The one boundary that talks to Firebase Auth and the native provider SDKs.
/// Everything above it sees [AuthAccount] and [SignInFailure] only.
abstract interface class AuthService {
  AuthAccount? get currentAccount;

  /// Interactive sign-in. Throws a [SignInFailure]; never returns null.
  Future<AuthAccount> signIn(AuthProviderKind provider);

  /// Re-runs the native flow and re-authenticates the current Firebase user.
  /// Needed only for client-side privileged operations; account deletion goes
  /// through the `deleteAccount` callable and does not require it.
  Future<void> reauthenticate(AuthProviderKind provider);

  /// Signs out of Firebase AND the Google SDK, so the next Google sign-in
  /// shows the account chooser again (v1 behaviour, kept).
  Future<void> signOut();
}

class FirebaseAuthService implements AuthService {
  FirebaseAuthService({required FirebaseAuth auth, GoogleSignIn? google, Random? random})
      : _auth = auth,
        _google = google ?? GoogleSignIn(scopes: const ['email']),
        _random = random ?? Random.secure();

  final FirebaseAuth _auth;
  final GoogleSignIn _google;
  final Random _random;

  @override
  AuthAccount? get currentAccount {
    final u = _auth.currentUser;
    return u == null ? null : accountOf(u);
  }

  static AuthAccount accountOf(User u) => AuthAccount(
        uid: u.uid,
        email: u.email,
        displayName: u.displayName,
        photoUrl: u.photoURL,
        providers: u.providerData.map((p) => p.providerId).toSet(),
      );

  @override
  Future<AuthAccount> signIn(AuthProviderKind provider) async {
    final credential = await _credentialFor(provider);
    try {
      final result = await _auth.signInWithCredential(credential);
      final user = result.user;
      if (user == null) throw SignInUnknown(provider, 'signInWithCredential returned no user');
      return accountOf(user);
    } on FirebaseAuthException catch (e) {
      throw _mapFirebase(provider, e);
    }
  }

  @override
  Future<void> reauthenticate(AuthProviderKind provider) async {
    final user = _auth.currentUser;
    if (user == null) throw SignInRejected(provider, 'no-current-user');
    final credential = await _credentialFor(provider);
    try {
      await user.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw _mapFirebase(provider, e);
    }
  }

  @override
  Future<void> signOut() async {
    // Google first: if Firebase sign-out succeeded but Google's did not, the
    // next sign-in would silently reuse the old account.
    try {
      await _google.signOut();
    } on Object catch (_) {
      // Not signed in with Google on this device — nothing to clear.
    }
    await _auth.signOut();
  }

  Future<AuthCredential> _credentialFor(AuthProviderKind provider) => switch (provider) {
        AuthProviderKind.google => _googleCredential(),
        AuthProviderKind.apple => _appleCredential(),
      };

  Future<AuthCredential> _googleCredential() async {
    const p = AuthProviderKind.google;
    final GoogleSignInAccount? account;
    try {
      account = await _google.signIn();
    } on Object catch (e) {
      final text = e.toString();
      // google_sign_in surfaces PlatformException codes as text; 10 = DEVELOPER_ERROR
      // (SHA-1 / client id mismatch), 7 = NETWORK_ERROR, 12501 = user cancelled.
      if (text.contains('12501') || text.contains('sign_in_canceled')) throw const SignInCancelled(p);
      if (text.contains('ApiException: 7') || text.contains('network_error')) throw SignInNetwork(p, text);
      if (text.contains('ApiException: 10')) throw SignInConfiguration(p, text);
      throw SignInUnknown(p, text);
    }
    if (account == null) throw const SignInCancelled(p);
    final auth = await account.authentication;
    if (auth.idToken == null && auth.accessToken == null) {
      throw SignInConfiguration(p, 'Google returned neither idToken nor accessToken');
    }
    return GoogleAuthProvider.credential(idToken: auth.idToken, accessToken: auth.accessToken);
  }

  Future<AuthCredential> _appleCredential() async {
    const p = AuthProviderKind.apple;
    // Firebase requires the nonce: raw in the credential, SHA-256 to Apple.
    // v1's "nonce" was the same character repeated — replay-able. Fixed.
    final rawNonce = generateNonce(_random);
    final AuthorizationCredentialAppleID apple;
    try {
      apple = await SignInWithApple.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
        nonce: sha256Hex(rawNonce),
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      throw switch (e.code) {
        AuthorizationErrorCode.canceled => const SignInCancelled(p),
        AuthorizationErrorCode.notHandled ||
        AuthorizationErrorCode.notInteractive ||
        AuthorizationErrorCode.invalidResponse =>
          SignInConfiguration(p, e.message),
        AuthorizationErrorCode.failed => SignInNetwork(p, e.message),
        AuthorizationErrorCode.unknown => SignInUnknown(p, e.message),
        // credentialExport / credentialImport / other future codes.
        _ => SignInUnknown(p, e.message),
      };
    } on SignInWithAppleNotSupportedException catch (e) {
      throw SignInConfiguration(p, e.message);
    }
    final idToken = apple.identityToken;
    if (idToken == null) throw SignInConfiguration(p, 'Apple returned no identityToken');
    return AppleAuthProvider.credentialWithIDToken(
      idToken,
      rawNonce,
      AppleFullPersonName(givenName: apple.givenName, familyName: apple.familyName),
    );
  }

  static SignInFailure _mapFirebase(AuthProviderKind p, FirebaseAuthException e) => switch (e.code) {
        'network-request-failed' => SignInNetwork(p, e.message),
        'invalid-credential' ||
        'operation-not-allowed' ||
        'invalid-api-key' ||
        'app-not-authorized' =>
          SignInConfiguration(p, '${e.code}: ${e.message}'),
        'account-exists-with-different-credential' ||
        'user-disabled' ||
        'user-not-found' ||
        'user-mismatch' ||
        'credential-already-in-use' =>
          SignInRejected(p, e.code, e.message),
        _ => SignInUnknown(p, '${e.code}: ${e.message}'),
      };

  /// 32 chars from a URL-safe alphabet, from a CSPRNG. Public + static so a
  /// test can pin the property (length, alphabet, uniqueness) without a device.
  static String generateNonce(Random random, [int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  static String sha256Hex(String input) => sha256.convert(utf8.encode(input)).toString();
}

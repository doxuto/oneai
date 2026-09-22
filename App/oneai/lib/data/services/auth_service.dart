import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:logging/logging.dart';

/// Interface for authentication services
abstract class AuthService {
  /// Current Firebase user if signed in, null otherwise
  Stream<User?> get authStateChanges;

  /// Returns currently signed-in user
  User? get currentUser;

  /// Sign in with Google
  Future<UserCredential> signInWithGoogle();

  /// Sign in with Apple
  Future<UserCredential> signInWithApple();

  /// Sign out current user
  Future<void> signOut();

  /// Delete current user account
  Future<void> deleteAccount();
}

/// Firebase implementation of AuthService
class FirebaseAuthService implements AuthService {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  // final GoogleSignIn _googleSignIn = GoogleSignIn(serverClientId: '468402655519-it1rgvjnifadq2dr0vot4m6h1ddqda18.apps.googleusercontent.com');

  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final _log = Logger('FirebaseAuthService');

  @override
  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  @override
  User? get currentUser => _firebaseAuth.currentUser;

  Future<OAuthCredential> getGoogleCredential() async {
    _log.info('Starting Google credential flow');
    // Begin interactive sign in process
    final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

    if (googleUser == null) {
      _log.warning('Google sign in aborted by user');
      throw Exception('Google sign in aborted by user');
    }

    // Obtain auth details from request
    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

    // Create new credential
    final OAuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    _log.info('Google credential obtained');
    return credential;
  }

  @override
  Future<UserCredential> signInWithGoogle() async {
    try {
      _log.info('Signing in with Google');
      final credential = await getGoogleCredential();
      final result = await _firebaseAuth.signInWithCredential(credential);
      _log.info('Google sign in successful');
      return result;
    } catch (e) {
      _log.severe('Google sign in failed: $e');
      if (e.toString().contains('ApiException: 10')) {
        throw Exception(
          'Google Sign In failed. This is likely due to a configuration issue. '
          'Please check that your SHA-1 fingerprint is correctly configured in the Firebase console '
          'and that you\'re using the correct OAuth client ID.',
        );
      }
      throw Exception('Google sign in failed: \\${e.toString()}');
    }
  }

  Future<OAuthCredential> getAppleCredential() async {
    _log.info('Starting Apple credential flow');
    // Generate a random nonce
    final rawNonce = _generateNonce();
    final nonce = _sha256ofString(rawNonce);

    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [AppleIDAuthorizationScopes.email, AppleIDAuthorizationScopes.fullName],
      nonce: nonce,
      webAuthenticationOptions: WebAuthenticationOptions(
        clientId: '468402655519-7n4hnnm9rhkgova6ioumv673peo0qu8n.apps.googleusercontent.com',
        redirectUri: Uri.parse('https://minutesai-6715a.firebaseapp.com/__/auth/handler'),
      ),
    );

    final fullName = AppleFullPersonName(familyName: appleCredential.familyName, givenName: appleCredential.givenName);

    final oauthCredential = AppleAuthProvider.credentialWithIDToken(
      appleCredential.identityToken ?? '',
      rawNonce,
      fullName,
    );

    _log.info('Apple credential obtained');
    return oauthCredential;
  }

  @override
  Future<UserCredential> signInWithApple() async {
    try {
      _log.info('Signing in with Apple');
      // Request credential for Apple
      final credential = await getAppleCredential();
      final result = await _firebaseAuth.signInWithCredential(credential);
      _log.info('Apple sign in successful');
      return result;
    } catch (e) {
      _log.severe('Apple sign in failed: $e');
      throw Exception('Apple sign in failed: \\${e.toString()}');
    }
  }

  @override
  Future<void> signOut() async {
    _log.info('Signing out user');
    await _googleSignIn.signOut();
    await _firebaseAuth.signOut();
    _log.info('User signed out');
  }

  /// Generates a cryptographically secure random nonce, to prevent replay attacks
  String _generateNonce([int length = 32]) {
    const charset = '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = DateTime.now().millisecondsSinceEpoch.toString();
    return List.generate(length, (_) => charset[random.hashCode % charset.length]).join();
  }

  /// Returns the sha256 hash of [input] in hex notation
  String _sha256ofString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Delete current user account
  @override
  Future<void> deleteAccount() async {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      _log.warning('No user is currently signed in');
      throw Exception('No user is currently signed in');
    }

    try {
      _log.info('Attempting to delete user account');
      await user.delete();
      _log.info('User account deleted successfully');
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        _log.warning('Delete account requires recent login, attempting re-auth');
        if (user.providerData.any((info) => info.providerId.contains('google'))) {
          final credential = await getGoogleCredential();
          await user.reauthenticateWithCredential(credential);
          _log.info('Re-authenticated with Google');
        } else if (user.providerData.any((info) => info.providerId.contains('apple'))) {
          final credential = await getAppleCredential();
          await user.reauthenticateWithCredential(credential);
          _log.info('Re-authenticated with Apple');
        } else {
          _log.severe('User is not signed in with Google or Apple');
          throw Exception('User is not signed in with Google or Apple');
        }
        await user.delete();
        _log.info('User account deleted successfully after re-auth');
      } else {
        _log.severe('Failed to delete account: ${e.toString()}');
        throw Exception('Failed to delete account: \\${e.toString()}');
      }
    }
  }
}

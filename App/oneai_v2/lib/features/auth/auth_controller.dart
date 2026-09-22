import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/core/errors/api_failure.dart';
import 'package:one_ai/data/repositories/user_repository.dart';
import 'package:one_ai/features/auth/auth_models.dart';
import 'package:one_ai/features/auth/auth_service.dart';
import 'package:one_ai/features/auth/billing_identity.dart';
import 'package:one_ai/features/auth/login_method_store.dart';

// ---- Wiring (overridden in tests) ----

final authServiceProvider = Provider<AuthService>(
  (ref) => FirebaseAuthService(auth: ref.watch(firebaseAuthProvider)),
);

final loginMethodStoreProvider = Provider<LoginMethodStore>((_) => const PrefsLoginMethodStore());

final billingIdentityProvider = Provider<BillingIdentity>((_) => const RevenueCatIdentity());

/// For the "(Previously signed in with …)" hint. Refreshed after each sign-in.
final lastLoginMethodProvider = FutureProvider<AuthProviderKind?>(
  (ref) => ref.watch(loginMethodStoreProvider).read(),
);

final authControllerProvider = NotifierProvider<AuthController, AuthFlow>(AuthController.new);

// ---- State ----

enum AuthAction { signInGoogle, signInApple, signOut, deleteAccount }

/// Progress of the *current* auth action. Whether the user is signed in is a
/// separate fact, owned by `authUserProvider` (the Firebase stream) — this
/// never duplicates it.
sealed class AuthFlow {
  const AuthFlow();
  bool get isBusy => this is AuthBusy;
}

final class AuthIdle extends AuthFlow {
  const AuthIdle();
}

final class AuthBusy extends AuthFlow {
  const AuthBusy(this.action);
  final AuthAction action;
}

final class AuthFailed extends AuthFlow {
  const AuthFailed(this.action, this.error);
  final AuthAction action;

  /// A [SignInFailure] for sign-in, an [ApiFailure] for deletion, anything
  /// for sign-out. [SignInCancelled] never lands here.
  final Object error;

  SignInFailure? get signInFailure => error is SignInFailure ? error as SignInFailure : null;
  ApiFailure? get apiFailure => error is ApiFailure ? error as ApiFailure : null;
}

// ---- Controller ----

class AuthController extends Notifier<AuthFlow> {
  @override
  AuthFlow build() => const AuthIdle();

  AuthService get _auth => ref.read(authServiceProvider);
  LoginMethodStore get _store => ref.read(loginMethodStoreProvider);
  BillingIdentity get _billing => ref.read(billingIdentityProvider);
  UserRepository get _users => ref.read(userRepositoryProvider);

  Future<void> signInWithGoogle() => _signIn(AuthProviderKind.google, AuthAction.signInGoogle);
  Future<void> signInWithApple() => _signIn(AuthProviderKind.apple, AuthAction.signInApple);

  Future<void> _signIn(AuthProviderKind provider, AuthAction action) async {
    if (state.isBusy) return;
    state = AuthBusy(action);
    try {
      final account = await _auth.signIn(provider);
      await _store.write(provider);
      ref.invalidate(lastLoginMethodProvider);
      // Purchases identity is best-effort: a RevenueCat outage must not turn a
      // successful sign-in into an error screen. The paywall re-tries logIn.
      await _guarded(() => _billing.logIn(account.uid), 'RevenueCat logIn');
      state = const AuthIdle();
    } on SignInCancelled {
      state = const AuthIdle();
    } on SignInFailure catch (e) {
      dev.log('sign-in failed', name: 'auth', error: e.debugMessage ?? e.runtimeType.toString());
      state = AuthFailed(action, e);
    } on Object catch (e) {
      dev.log('sign-in crashed', name: 'auth', error: e);
      state = AuthFailed(action, SignInUnknown(provider, e.toString()));
    }
  }

  Future<void> signOut() async {
    if (state.isBusy) return;
    state = const AuthBusy(AuthAction.signOut);
    try {
      await _guarded(_billing.logOut, 'RevenueCat logOut');
      await _auth.signOut();
      state = const AuthIdle();
    } on Object catch (e) {
      state = AuthFailed(AuthAction.signOut, e);
    }
  }

  /// Server-side deletion via the `deleteAccount` callable (which removes the
  /// Auth user and, through `onUserDeleted`, every document and file). The
  /// local SDK would only notice at its next token refresh, so sign out
  /// explicitly afterwards to leave the signed-in state right away.
  Future<void> deleteAccount() async {
    if (state.isBusy) return;
    state = const AuthBusy(AuthAction.deleteAccount);
    try {
      await _users.deleteAccount();
    } on Object catch (e) {
      state = AuthFailed(AuthAction.deleteAccount, e);
      return;
    }
    await _guarded(_billing.logOut, 'RevenueCat logOut');
    await _guarded(_auth.signOut, 'local signOut after delete');
    state = const AuthIdle();
  }

  void dismissError() {
    if (state is AuthFailed) state = const AuthIdle();
  }

  Future<void> _guarded(Future<void> Function() op, String what) async {
    try {
      await op();
    } on Object catch (e) {
      dev.log('$what failed (ignored)', name: 'auth', error: e);
    }
  }
}

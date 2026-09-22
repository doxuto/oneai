import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/core/errors/api_failure.dart';
import 'package:one_ai/data/models/user_models.dart';
import 'package:one_ai/data/repositories/user_repository.dart';
import 'package:one_ai/features/auth/auth_controller.dart';
import 'package:one_ai/features/auth/auth_models.dart';
import 'package:one_ai/features/auth/auth_service.dart';
import 'package:one_ai/features/auth/billing_identity.dart';
import 'package:one_ai/features/auth/login_method_store.dart';

// ---- Fakes: record calls, throw on demand ----

class FakeAuthService implements AuthService {
  final calls = <String>[];
  Object? signInError;
  Object? signOutError;
  AuthAccount? account;

  @override
  AuthAccount? get currentAccount => account;

  @override
  Future<AuthAccount> signIn(AuthProviderKind provider) async {
    calls.add('signIn:${provider.name}');
    if (signInError != null) throw signInError!;
    return account = AuthAccount(uid: 'uid-${provider.name}', providers: {provider.firebaseProviderId});
  }

  @override
  Future<void> reauthenticate(AuthProviderKind provider) async => calls.add('reauth:${provider.name}');

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    if (signOutError != null) throw signOutError!;
    account = null;
  }
}

class FakeBilling implements BillingIdentity {
  final calls = <String>[];
  Object? error;
  @override
  Future<void> logIn(String uid) async {
    calls.add('logIn:$uid');
    if (error != null) throw error!;
  }

  @override
  Future<void> logOut() async {
    calls.add('logOut');
    if (error != null) throw error!;
  }
}

class FakeUsers implements UserRepository {
  int deletes = 0;
  Object? deleteError;
  @override
  Future<void> deleteAccount() async {
    deletes++;
    if (deleteError != null) throw deleteError!;
  }

  @override
  Future<Me> me() => throw UnimplementedError();
  @override
  Stream<Quota?> watchQuota(String uid, {required String periodId, required int fallbackLimit, required DateTime resetAt}) =>
      throw UnimplementedError();
}

class Harness {
  Harness() {
    container = ProviderContainer.test(
      overrides: [
        authServiceProvider.overrideWithValue(auth),
        billingIdentityProvider.overrideWithValue(billing),
        loginMethodStoreProvider.overrideWithValue(store),
        userRepositoryProvider.overrideWithValue(users),
      ],
    );
  }
  final auth = FakeAuthService();
  final billing = FakeBilling();
  final store = InMemoryLoginMethodStore();
  final users = FakeUsers();
  late final ProviderContainer container;

  AuthController get ctl => container.read(authControllerProvider.notifier);
  AuthFlow get state => container.read(authControllerProvider);
}

void main() {
  group('sign-in', () {
    test('happy path: signs in, remembers method, binds RevenueCat, ends idle', () async {
      final h = Harness();
      await h.ctl.signInWithGoogle();
      expect(h.state, isA<AuthIdle>());
      expect(h.auth.calls, ['signIn:google']);
      expect(h.store.value, AuthProviderKind.google);
      expect(h.billing.calls, ['logIn:uid-google']);
      expect(await h.container.read(lastLoginMethodProvider.future), AuthProviderKind.google);
    });

    test('apple goes through the same path with its own action', () async {
      final h = Harness();
      final seen = <AuthFlow>[];
      h.container.listen(authControllerProvider, (_, next) => seen.add(next), fireImmediately: true);
      await h.ctl.signInWithApple();
      expect(seen.whereType<AuthBusy>().single.action, AuthAction.signInApple);
      expect(h.store.value, AuthProviderKind.apple);
    });

    test('cancel is silent: back to idle, nothing persisted, no billing call', () async {
      final h = Harness()..auth.signInError = const SignInCancelled(AuthProviderKind.google);
      await h.ctl.signInWithGoogle();
      expect(h.state, isA<AuthIdle>());
      expect(h.store.value, isNull);
      expect(h.billing.calls, isEmpty);
    });

    test('provider failure surfaces as AuthFailed with the SignInFailure', () async {
      final h = Harness()..auth.signInError = const SignInConfiguration(AuthProviderKind.google, 'ApiException: 10');
      await h.ctl.signInWithGoogle();
      final failed = h.state as AuthFailed;
      expect(failed.action, AuthAction.signInGoogle);
      expect(failed.signInFailure, isA<SignInConfiguration>());
      expect(h.store.value, isNull);
    });

    test('unexpected exception is wrapped as SignInUnknown, never leaks', () async {
      final h = Harness()..auth.signInError = StateError('boom');
      await h.ctl.signInWithGoogle();
      expect((h.state as AuthFailed).signInFailure, isA<SignInUnknown>());
    });

    test('RevenueCat outage does not fail a successful sign-in', () async {
      final h = Harness()..billing.error = Exception('rc down');
      await h.ctl.signInWithGoogle();
      expect(h.state, isA<AuthIdle>());
      expect(h.auth.account, isNotNull);
    });

    test('re-entrancy: a second tap while busy is ignored', () async {
      final h = Harness();
      final first = h.ctl.signInWithGoogle();
      await h.ctl.signInWithApple(); // returns immediately
      await first;
      expect(h.auth.calls, ['signIn:google']);
    });

    test('dismissError returns to idle only from failed', () async {
      final h = Harness()..auth.signInError = const SignInNetwork(AuthProviderKind.apple);
      await h.ctl.signInWithApple();
      expect(h.state, isA<AuthFailed>());
      h.ctl.dismissError();
      expect(h.state, isA<AuthIdle>());
      h.ctl.dismissError();
      expect(h.state, isA<AuthIdle>());
    });
  });

  group('sign-out', () {
    test('logs out of RevenueCat first, then Firebase', () async {
      final h = Harness();
      await h.ctl.signInWithGoogle();
      h.billing.calls.clear();
      await h.ctl.signOut();
      expect(h.state, isA<AuthIdle>());
      expect(h.billing.calls, ['logOut']);
      expect(h.auth.calls.last, 'signOut');
      expect(h.auth.account, isNull);
    });

    test('billing failure is ignored, Firebase sign-out still happens', () async {
      final h = Harness()..billing.error = Exception('rc');
      await h.ctl.signOut();
      expect(h.state, isA<AuthIdle>());
      expect(h.auth.calls, ['signOut']);
    });

    test('Firebase sign-out failure is reported', () async {
      final h = Harness()..auth.signOutError = Exception('net');
      await h.ctl.signOut();
      expect((h.state as AuthFailed).action, AuthAction.signOut);
    });
  });

  group('delete account', () {
    test('calls the callable once, then clears billing + local session', () async {
      final h = Harness();
      await h.ctl.signInWithGoogle();
      h.auth.calls.clear();
      h.billing.calls.clear();
      await h.ctl.deleteAccount();
      expect(h.users.deletes, 1);
      expect(h.billing.calls, ['logOut']);
      expect(h.auth.calls, ['signOut']);
      expect(h.state, isA<AuthIdle>());
    });

    test('server refusal keeps the session and surfaces the ApiFailure', () async {
      final h = Harness()..users.deleteError = const PermissionFailure('nope', null);
      await h.ctl.signInWithGoogle();
      h.auth.calls.clear();
      await h.ctl.deleteAccount();
      final failed = h.state as AuthFailed;
      expect(failed.action, AuthAction.deleteAccount);
      expect(failed.apiFailure, isA<PermissionFailure>());
      expect(h.auth.calls, isEmpty, reason: 'must not sign out when deletion failed');
      expect(h.auth.account, isNotNull);
    });

    test('local sign-out failure after a successful delete is not an error', () async {
      final h = Harness()..auth.signOutError = Exception('offline');
      await h.ctl.deleteAccount();
      expect(h.users.deletes, 1);
      expect(h.state, isA<AuthIdle>());
    });
  });
}

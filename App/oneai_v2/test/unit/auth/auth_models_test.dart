import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/features/auth/auth_models.dart';
import 'package:one_ai/features/auth/auth_service.dart';

void main() {
  group('AuthProviderKind', () {
    test('storage keys are the v1 values, so the hint survives an upgrade', () {
      expect(AuthProviderKind.google.storageKey, 'google');
      expect(AuthProviderKind.apple.storageKey, 'apple');
      expect(AuthProviderKind.fromStorageKey('apple'), AuthProviderKind.apple);
      expect(AuthProviderKind.fromStorageKey('facebook'), isNull);
      expect(AuthProviderKind.fromStorageKey(null), isNull);
    });
  });

  group('AuthAccount.primaryProvider', () {
    test('picks google, then apple, else null', () {
      expect(const AuthAccount(uid: 'u', providers: {'apple.com', 'google.com'}).primaryProvider, AuthProviderKind.google);
      expect(const AuthAccount(uid: 'u', providers: {'apple.com'}).primaryProvider, AuthProviderKind.apple);
      expect(const AuthAccount(uid: 'u', providers: {'password'}).primaryProvider, isNull);
      expect(const AuthAccount(uid: 'u').primaryProvider, isNull);
    });
  });

  group('Apple nonce', () {
    test('is 32 chars from the URL-safe alphabet and differs per call', () {
      final r = Random(7);
      final a = FirebaseAuthService.generateNonce(r);
      final b = FirebaseAuthService.generateNonce(r);
      expect(a.length, 32);
      expect(RegExp(r'^[0-9A-Za-z\-._]+$').hasMatch(a), isTrue);
      expect(a, isNot(equals(b)));
      // v1 regression: the same character repeated 32 times.
      expect(a.split('').toSet().length, greaterThan(1));
    });

    test('sha256Hex matches the known digest of "abc"', () {
      expect(
        FirebaseAuthService.sha256Hex('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });
  });
}

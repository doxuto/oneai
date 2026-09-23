import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/core/errors/api_failure.dart';
import 'package:one_ai/data/models/user_models.dart';
import 'package:one_ai/data/repositories/push_repository.dart';
import 'package:one_ai/features/notifications/push_messaging.dart';
import 'package:one_ai/features/notifications/push_registrar.dart';

class FakeMessaging implements PushMessaging {
  bool permission = true;
  String? token = 'tok-1';
  final refresh = StreamController<String>.broadcast();
  final opened = StreamController<Map<String, String>>.broadcast();
  Map<String, String>? initial;
  final calls = <String>[];

  @override
  Future<bool> requestPermission() async {
    calls.add('requestPermission');
    return permission;
  }

  @override
  Future<String?> getToken() async => token;
  @override
  Stream<String> get onTokenRefresh => refresh.stream;
  @override
  Stream<Map<String, String>> get onNotificationOpened => opened.stream;
  @override
  Future<Map<String, String>?> initialMessageData() async => initial;
  @override
  Future<void> deleteToken() async => calls.add('deleteToken');
}

class FakePushRepo implements PushRepository {
  final calls = <String>[];
  Object? error;
  @override
  Future<void> registerDevice({required String token, String? locale}) async {
    calls.add('register:$token:$locale');
    if (error != null) throw error!;
  }

  @override
  Future<void> unregisterDevice(String token) async => calls.add('unregister:$token');
  @override
  Future<NotificationPrefs> updatePrefs({required bool transcriptionDone}) async => NotificationPrefs(transcriptionDone: transcriptionDone);
}

/// The registrar only reads `.uid` off the Firebase user; a minimal stand-in.
class FakeUser implements User {
  FakeUser(this.uid);
  @override
  final String uid;
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

class Harness {
  Harness() {
    container = ProviderContainer.test(overrides: [
      pushMessagingProvider.overrideWithValue(fm),
      pushRepositoryProvider.overrideWithValue(repo),
      deviceLocaleTagProvider.overrideWithValue('vi-VN'),
      authUserProvider.overrideWith((ref) => auth.stream),
    ]);
    container.listen(pushRegistrarProvider, (_, __) {});
  }
  final fm = FakeMessaging();
  final repo = FakePushRepo();
  final auth = StreamController<User?>.broadcast();
  late final ProviderContainer container;
  PushState get state => container.read(pushRegistrarProvider);
  PushRegistrar get reg => container.read(pushRegistrarProvider.notifier);
}

Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('registers the current token with the device locale once the user signs in', () async {
    final h = Harness();
    await settle();
    expect(h.repo.calls, isEmpty);
    h.auth.add(FakeUser('u1'));
    await settle();
    expect(h.repo.calls, ['register:tok-1:vi-VN']);
    expect(h.state.registeredToken, 'tok-1');
  });

  test('token rotation re-registers; the same token is not re-sent', () async {
    final h = Harness();
    h.auth.add(FakeUser('u1'));
    await settle();
    h.fm.refresh.add('tok-2');
    await settle();
    h.fm.refresh.add('tok-2');
    await settle();
    expect(h.repo.calls, ['register:tok-1:vi-VN', 'register:tok-2:vi-VN']);
  });

  test('no token (permission not granted / simulator) → nothing is sent', () async {
    final h = Harness()..fm.token = null;
    h.auth.add(FakeUser('u1'));
    await settle();
    expect(h.repo.calls, isEmpty);
    expect(h.state.registeredToken, isNull);
  });

  test('requestPermission: granted → registers; denied → recorded, nothing sent', () async {
    final h = Harness();
    h.auth.add(FakeUser('u1'));
    h.fm.token = null;
    await settle();
    h.fm.token = 'tok-1';
    expect(await h.reg.requestPermission(), isTrue);
    expect(h.state.permission, PushPermission.granted);
    expect(h.repo.calls, ['register:tok-1:vi-VN']);

    final d = Harness()..fm.permission = false;
    d.auth.add(FakeUser('u1'));
    d.fm.token = null;
    await settle();
    expect(await d.reg.requestPermission(), isFalse);
    expect(d.state.permission, PushPermission.denied);
    expect(d.repo.calls, isEmpty);
  });

  test('register failure is kept as lastError and retried on the next sync', () async {
    final h = Harness()..repo.error = const TransientFailure('x');
    h.auth.add(FakeUser('u1'));
    await settle();
    expect(h.state.registeredToken, isNull);
    expect(h.state.lastError, isA<TransientFailure>());
    h.repo.error = null;
    await h.reg.syncNow();
    expect(h.state.registeredToken, 'tok-1');
    expect(h.state.lastError, isNull);
  });

  test('unregisterBeforeSignOut tells the server while auth is still valid; sign-out then drops the local token', () async {
    final h = Harness();
    h.auth.add(FakeUser('u1'));
    await settle();
    await h.reg.unregisterBeforeSignOut();
    expect(h.repo.calls.last, 'unregister:tok-1');
    expect(h.state.registeredToken, isNull);
    h.auth.add(null);
    await settle();
    expect(h.fm.calls, contains('deleteToken'));
    // Signing in as someone else registers again.
    h.auth.add(FakeUser('u2'));
    await settle();
    expect(h.repo.calls.last, 'register:tok-1:vi-VN');
  });

  group('PushTap', () {
    test('parses routing data and ignores incomplete payloads', () {
      expect(PushTap.fromData({'type': 'minuteReady', 'minuteId': 'm1'})?.minuteId, 'm1');
      expect(PushTap.fromData({'type': 'minuteReady'}), isNull);
      expect(PushTap.fromData(null), isNull);
    });

    test('pushTapProvider yields the cold-start tap first, then later taps', () async {
      final h = Harness()..fm.initial = {'type': 'minuteFailed', 'minuteId': 'm0'};
      final taps = <PushTap>[];
      h.container.listen(pushTapProvider, (_, next) {
        final v = next.valueOrNull;
        if (v != null) taps.add(v);
      });
      await settle();
      h.fm.opened.add({'type': 'minuteReady', 'minuteId': 'm1'});
      await settle();
      expect(taps.map((t) => t.minuteId), ['m0', 'm1']);
    });
  });
}

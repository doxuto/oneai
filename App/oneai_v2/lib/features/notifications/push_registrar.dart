import 'dart:async';
import 'dart:developer' as dev;
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:one_ai/core/di/providers.dart';
import 'package:one_ai/data/repositories/push_repository.dart';
import 'package:one_ai/features/notifications/push_messaging.dart';

// ---- Wiring ----

final pushMessagingProvider = Provider<PushMessaging>((_) => FirebasePushMessaging());

final pushRepositoryProvider = Provider<PushRepository>(
  (ref) => PushRepository(functions: ref.watch(functionsClientProvider)),
);

/// Device locale as BCP-47, sent so the server picks the notification language.
final deviceLocaleTagProvider = Provider<String?>((_) {
  try {
    return PlatformDispatcher.instance.locale.toLanguageTag();
  } on Object catch (_) {
    return null;
  }
});

final pushRegistrarProvider = NotifierProvider<PushRegistrar, PushState>(PushRegistrar.new);

// ---- State ----

enum PushPermission { unknown, granted, denied }

class PushState {
  const PushState({this.permission = PushPermission.unknown, this.registeredToken, this.lastError});

  final PushPermission permission;

  /// The token the server currently holds for this device+user, or null.
  final String? registeredToken;
  final Object? lastError;

  PushState copyWith({PushPermission? permission, String? registeredToken = _keep, Object? lastError = _keep}) => PushState(
        permission: permission ?? this.permission,
        registeredToken: identical(registeredToken, _keep) ? this.registeredToken : registeredToken as String?,
        lastError: identical(lastError, _keep) ? this.lastError : lastError,
      );
}

const Object _keep = Object();

/// A notification tap the router should act on.
class PushTap {
  const PushTap({required this.type, required this.minuteId});
  final String type;
  final String minuteId;

  static PushTap? fromData(Map<String, String>? data) {
    final id = data?['minuteId'];
    final type = data?['type'];
    if (id == null || id.isEmpty || type == null) return null;
    return PushTap(type: type, minuteId: id);
  }
}

// ---- Registrar ----

/// Keeps the server's token registry in step with (signed-in user × FCM
/// token): registers after sign-in and on token rotation, unregisters on
/// sign-out. Never asks for permission on its own — [requestPermission] is
/// called from the UI at a sensible moment (after the first recording), not
/// on cold start, so the OS prompt has context.
class PushRegistrar extends Notifier<PushState> {
  StreamSubscription<String>? _refreshSub;
  String? _uid;

  PushMessaging get _fm => ref.read(pushMessagingProvider);
  PushRepository get _repo => ref.read(pushRepositoryProvider);

  @override
  PushState build() {
    ref.onDispose(() => unawaited(_refreshSub?.cancel()));
    _refreshSub = _fm.onTokenRefresh.listen((t) => unawaited(_register(t)));
    ref.listen(authUserProvider, (_, next) {
      final uid = next.valueOrNull?.uid;
      if (uid == _uid) return;
      final previous = _uid;
      _uid = uid;
      if (uid == null) {
        unawaited(_unregister(previous));
      } else {
        unawaited(syncNow());
      }
    }, fireImmediately: true);
    return const PushState();
  }

  /// Show the OS prompt (once), then register. Safe to call repeatedly.
  Future<bool> requestPermission() async {
    final ok = await _fm.requestPermission();
    state = state.copyWith(permission: ok ? PushPermission.granted : PushPermission.denied);
    if (ok) await syncNow();
    return ok;
  }

  /// Registers the current token if signed in. No-op when there is no token
  /// (permission not granted yet, simulator).
  Future<void> syncNow() async {
    if (_uid == null) return;
    final token = await _fm.getToken();
    if (token == null) return;
    await _register(token);
  }

  Future<void> _register(String token) async {
    if (_uid == null) return;
    if (state.registeredToken == token) return;
    try {
      await _repo.registerDevice(token: token, locale: ref.read(deviceLocaleTagProvider));
      state = state.copyWith(registeredToken: token, lastError: null);
    } on Object catch (e) {
      dev.log('registerDevice failed', name: 'push', error: e);
      state = state.copyWith(lastError: e);
    }
  }

  Future<void> _unregister(String? previousUid) async {
    final token = state.registeredToken;
    state = state.copyWith(registeredToken: null);
    if (token == null || previousUid == null) return;
    try {
      // The user is already signed out here, so this call carries no auth
      // and would be rejected; the server also moves the token to the next
      // account on register. Best effort only — delete the local token so a
      // stale one is never re-sent.
      await _fm.deleteToken();
    } on Object catch (e) {
      dev.log('deleteToken failed', name: 'push', error: e);
    }
  }

  /// Called by AuthController *before* signing out, while the call still
  /// carries the user's auth.
  Future<void> unregisterBeforeSignOut() async {
    final token = state.registeredToken;
    if (token == null) return;
    try {
      await _repo.unregisterDevice(token);
    } on Object catch (e) {
      dev.log('unregisterDevice failed', name: 'push', error: e);
    }
    state = state.copyWith(registeredToken: null);
  }
}

/// Notification taps (cold start + background), as routing intents.
final pushTapProvider = StreamProvider<PushTap>((ref) async* {
  final fm = ref.watch(pushMessagingProvider);
  final initial = PushTap.fromData(await fm.initialMessageData());
  if (initial != null) yield initial;
  await for (final data in fm.onNotificationOpened) {
    final tap = PushTap.fromData(data);
    if (tap != null) yield tap;
  }
});

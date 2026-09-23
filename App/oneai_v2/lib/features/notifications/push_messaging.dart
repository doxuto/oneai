import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

/// What the app needs from FCM, narrowed so the registrar can be tested
/// with a fake. The real one wraps `FirebaseMessaging.instance`.
abstract interface class PushMessaging {
  /// Asks the OS (iOS: the system prompt; Android 13+: POST_NOTIFICATIONS).
  /// Returns whether notifications are allowed (provisional counts as yes).
  Future<bool> requestPermission();

  /// Current token, or null when unavailable (simulator, permission denied).
  Future<String?> getToken();

  /// Fires when FCM rotates the token; the registrar re-registers.
  Stream<String> get onTokenRefresh;

  /// Tap on a notification that opened or resumed the app. Payload = `data`.
  Stream<Map<String, String>> get onNotificationOpened;

  /// The notification that launched the app from a terminated state, if any.
  Future<Map<String, String>?> initialMessageData();

  Future<void> deleteToken();
}

class FirebasePushMessaging implements PushMessaging {
  FirebasePushMessaging([FirebaseMessaging? messaging]) : _fm = messaging ?? FirebaseMessaging.instance;
  final FirebaseMessaging _fm;

  @override
  Future<bool> requestPermission() async {
    final s = await _fm.requestPermission();
    final ok = s.authorizationStatus == AuthorizationStatus.authorized || s.authorizationStatus == AuthorizationStatus.provisional;
    if (ok) {
      // iOS: show the banner even while the app is in the foreground; the
      // in-app Firestore listener already updates the list, so this is just
      // the heads-up. Android shows foreground notifications by default only
      // through a local notification — we skip that: the list updates live.
      await _fm.setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true);
    }
    return ok;
  }

  @override
  Future<String?> getToken() async {
    try {
      return await _fm.getToken();
    } on Object catch (_) {
      return null; // simulator / no APNs token yet
    }
  }

  @override
  Stream<String> get onTokenRefresh => _fm.onTokenRefresh;

  @override
  Stream<Map<String, String>> get onNotificationOpened =>
      FirebaseMessaging.onMessageOpenedApp.map((m) => m.data.map((k, v) => MapEntry(k, v.toString())));

  @override
  Future<Map<String, String>?> initialMessageData() async {
    final m = await _fm.getInitialMessage();
    return m?.data.map((k, v) => MapEntry(k, v.toString()));
  }

  @override
  Future<void> deleteToken() => _fm.deleteToken();
}

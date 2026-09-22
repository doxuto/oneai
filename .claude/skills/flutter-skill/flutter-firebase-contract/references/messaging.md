# Messaging

`firebase_messaging` 16.7.0 — the Flutter half of push. Everything that decides *what* is sent — payload shape, topics vs tokens, batching, `sendEachForMulticast`, token cleanup on `messaging/registration-token-not-registered` — is `firebase-skill` → `fcm-push-pro`. This file is about the app: permission, the token, the three delivery states, and taps.

## Permission

```dart
final settings = await FirebaseMessaging.instance.requestPermission(
  alert: true,
  badge: true,
  sound: true,
  provisional: false,
);

final granted = switch (settings.authorizationStatus) {
  AuthorizationStatus.authorized || AuthorizationStatus.provisional => true,
  _ => false,
};
```

`requestPermission({bool alert = true, bool announcement = false, bool badge = true, bool carPlay = false, bool criticalAlert = false, bool provisional = false, bool sound = true, bool providesAppNotificationSettings = false}) → Future<NotificationSettings>`.

`AuthorizationStatus` has five members: `authorized`, `denied`, `notDetermined`, `provisional`, `deniedPermanently`.

- Ask at a moment the user understands, not in `main()`. The system prompt appears once; a denial is durable and, on `deniedPermanently`, cannot be asked again — the only path back is the OS settings screen.
- `provisional: true` grants quiet delivery on iOS with no prompt: notifications arrive in the notification centre and the user promotes or turns them off from there. Good for a first-run default.
- Android 13+ (API 33) also requires the runtime `POST_NOTIFICATIONS` permission; `requestPermission` triggers it. Below API 33 it returns `authorized` without a prompt.
- Check `getNotificationSettings()` on resume rather than caching the answer — the user can revoke it in Settings while the app is backgrounded.
- Data-only messages are delivered without notification permission. If push is purely a sync signal, do not ask at all.

## The token

```dart
Future<void> registerToken(WidgetRef ref) async {
  final messaging = FirebaseMessaging.instance;

  if (Platform.isIOS || Platform.isMacOS) {
    final apns = await messaging.getAPNSToken();
    if (apns == null) return;     // APNs not ready yet — retry later, do not call getToken
  }

  final token = await messaging.getToken();
  if (token != null) {
    await ref.read(pushRepositoryProvider).registerDeviceToken(token);
  }
}

// Long-lived, set up once at startup:
FirebaseMessaging.instance.onTokenRefresh.listen((token) {
  ref.read(pushRepositoryProvider).registerDeviceToken(token);
});
```

| Member | Signature |
|---|---|
| `getToken` | `Future<String?> getToken({String? vapidKey, String? serviceWorkerScriptPath})` |
| `onTokenRefresh` | `Stream<String>` (instance property) |
| `deleteToken` | `Future<void> deleteToken()` |
| `getAPNSToken` | `Future<String?> getAPNSToken()` |
| `setAutoInitEnabled` | `Future<void> setAutoInitEnabled(bool)` |

- On Apple platforms the APNs token must be available before other FCM APIs are called (a requirement since iOS SDK 10.4.0). `getAPNSToken()` returns `null` until it is. Guard `getToken()` with it rather than retrying blindly.
- `onTokenRefresh` must be subscribed for the life of the app, not just around the first registration. A token rotates on reinstall, restore-from-backup, and occasionally on its own, and a stale token is a silently undelivered notification.
- Registering the token is a callable (`registerDeviceToken`) like any other, with the same contract rules: the server takes the token from the request body and the `uid` from `request.auth`. It stores `{ token, platform, appVersion, updatedAt }` under the user.
- `deleteToken()` on sign-out, then re-register after the next sign-in. Otherwise the next user of the device receives the previous user's notifications.
- `vapidKey` is web only.
- `setAutoInitEnabled(false)` stops FCM generating a token until the user opts in — the right default where a privacy notice must come first.

## The three delivery states

| App state | Notification message | Data-only message |
|---|---|---|
| Foreground | `FirebaseMessaging.onMessage` fires; no system notification is shown unless you ask for one | `onMessage` fires |
| Background | System tray shows it; `onMessage` does **not** fire; `onBackgroundMessage` handler runs | `onBackgroundMessage` handler runs |
| Terminated | System tray shows it; `onBackgroundMessage` handler runs | Android: handler runs. iOS: delivery is best-effort and requires `content-available` |
| Tapped from tray (app backgrounded) | `FirebaseMessaging.onMessageOpenedApp` fires | n/a |
| Tapped from tray (app terminated) | `FirebaseMessaging.instance.getInitialMessage()` returns it, once | n/a |

```dart
// Foreground: decide what the user sees. FCM shows nothing by itself.
FirebaseMessaging.onMessage.listen((message) {
  final notification = message.notification;
  if (notification != null) showInAppBanner(notification.title, notification.body);
  ref.read(inboxProvider.notifier).markStale();
});

// iOS only — let the system present a foreground notification instead of an in-app banner.
await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
  alert: true,
  badge: true,
  sound: true,
);
```

## The background handler

```dart
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // Minimal work only: a local notification, a cache write, an analytics event.
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  runApp(const ProviderScope(child: MyApp()));
}
```

Three requirements, all enforced by the plugin and all easy to break:

1. It must be a **top-level** function — not a method, not a closure, not a static member of a class.
2. It must not be **anonymous**.
3. On Flutter 3.3.0 and above it must be annotated `@pragma('vm:entry-point')`, or tree-shaking removes it from release builds and the handler silently never runs.

And two consequences:

- It runs in a **separate isolate** with a fresh memory space. It has no access to your `ProviderScope`, your singletons, or anything you set up in `main()`. It must call `Firebase.initializeApp` itself.
- It has a short execution budget. Do not start a long upload or a chain of callables there. Write a marker the app reads on next launch.

Register it before `runApp` and only once.

## Taps and deep links

```dart
Future<void> wireNotificationTaps(WidgetRef ref) async {
  // App was terminated and launched by the tap.
  final initial = await FirebaseMessaging.instance.getInitialMessage();
  if (initial != null) _handle(ref, initial);

  // App was backgrounded.
  FirebaseMessaging.onMessageOpenedApp.listen((message) => _handle(ref, message));
}

void _handle(WidgetRef ref, RemoteMessage message) {
  final route = message.data['route'] as String?;   // data is Map<String, dynamic>
  if (route != null) ref.read(routerProvider).go(route);
}
```

- `getInitialMessage()` returns the launch message once. Call it after the router exists; calling it in `main()` before `runApp` means navigating to a route that has no `Navigator` yet.
- Both paths must funnel into the same `_handle`, or a deep link works from one state and not the other — the classic "works when I test it, not when the user gets it".
- `RemoteMessage.data` is `Map<String, dynamic>`, but FCM data values are always strings on the wire. Anything structured must be a JSON string the app decodes, and a route id is cheaper than an embedded payload. The message is a signal; fetch the real data with a callable or a listener.
- Never trust `data` as authorisation. Anyone can craft a local notification; the server must still check the caller.
- Notification tap handling has no relationship to `onBackgroundMessage`. Both can fire for the same message.

## `RemoteMessage`

| Field | Type |
|---|---|
| `data` | `Map<String, dynamic>` |
| `notification` | `RemoteNotification?` |
| `messageId` | `String?` |
| `senderId` | `String?` |
| `sentTime` | `DateTime?` |
| `contentAvailable` | `bool` |
| `mutableContent` | `bool` |
| `collapseKey` | `String?` |
| `category` | `String?` |
| `threadId` | `String?` |
| `ttl` | `int?` |
| `from` | `String?` |
| `messageType` | `String?` |

`notification == null` means a data-only message. Branch on that rather than on the presence of a particular data key.

## iOS prerequisites

Push on iOS fails silently when any of these is missing, and the failure looks identical in all cases:

1. An APNs authentication key (`.p8`) or certificate uploaded in the Firebase console, for the right team and bundle id.
2. The **Push Notifications** capability added to the Xcode target.
3. **Background Modes → Remote notifications** enabled, required for `content-available` data messages.
4. A real device. The iOS simulator does not receive push from APNs.
5. `getAPNSToken()` returning non-null before other FCM calls.

A data-only message on iOS also needs `content-available: 1` from the server, and even then delivery is throttled at the system's discretion. Treat it as a hint to sync, never as a guaranteed event; the server-side payload rules are `firebase-skill` → `fcm-push-pro`.

Android 8+ needs a notification channel for anything with a custom sound or importance. `firebase_messaging` uses a default channel; a custom one is created through `flutter_local_notifications` and named in the server payload.

## Does not exist / common mistakes

- A background handler declared as a static method or a closure — must be top-level.
- A background handler without `@pragma('vm:entry-point')` — works in debug, tree-shaken out of release.
- A background handler that uses `ref` or a singleton from `main()` — different isolate, none of it exists.
- A background handler that does not call `Firebase.initializeApp` — every Firebase call inside it throws.
- Expecting `onMessage` to fire while the app is backgrounded — it does not; that is `onBackgroundMessage`.
- Expecting FCM to display a banner while the app is in the foreground — it does not, unless you call `setForegroundNotificationPresentationOptions` on iOS or show a local notification yourself.
- Calling `getInitialMessage()` in `main()` before the router exists — nowhere to navigate to.
- Handling taps only in `onMessageOpenedApp` — the terminated-launch case is `getInitialMessage()`.
- Calling `getToken()` on iOS before `getAPNSToken()` returns non-null.
- Registering the token once at first launch and never listening to `onTokenRefresh` — tokens rotate.
- Not calling `deleteToken()` at sign-out — the next user gets the previous user's notifications.
- Putting a JSON object into `data` and expecting a nested map — FCM data values are strings; encode and decode explicitly.
- Testing push on the iOS simulator.

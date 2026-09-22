# iOS client (Swift, SwiftUI, TCA)

The client does five things: ask permission, register, upload the token, present, and turn a tap into an action. Keep everything else out of the AppDelegate. Reducer/dependency shape is covered by `tca-pro` (`references/dependencies.md`, `references/effects.md`); SwiftUI lifecycle by `swiftui-pro`.

## Info.plist / capabilities

- Signing & Capabilities → **Push Notifications**.
- Background Modes → **Remote notifications** (only if you send silent pushes).
- `FirebaseAppDelegateProxyEnabled` = `NO` if you want to own the delegate wiring explicitly (recommended in a TCA app; then forward `apnsToken` and `appDidReceiveMessage` yourself as shown below). With swizzling on (default), Firebase hooks the APNs token for you.
- APNs auth key (.p8) uploaded in Firebase console → Project settings → Cloud Messaging. Without it nothing arrives on iOS while the server reports success.

## App entry and delegate

```swift
import SwiftUI
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import ComposableArchitecture

@main
struct SnapToolApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  var body: some Scene {
    WindowGroup { AppView(store: appDelegate.store) }
  }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
  let store = Store(initialState: AppFeature.State()) { AppFeature() }

  func application(_ application: UIApplication,
                   didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    FirebaseApp.configure()                       // after AppCheck factory, if used
    UNUserNotificationCenter.current().delegate = self
    Messaging.messaging().delegate = self
    NotificationCategories.registerAll()          // UNNotificationCategory set — see silent-and-rich.md
    application.registerForRemoteNotifications()  // safe before authorization; needed for silent + token
    store.send(.appDelegate(.didFinishLaunching))
    return true
  }

  // 1. APNs token → FCM. Must happen before the FCM token is read or uploaded.
  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Messaging.messaging().apnsToken = deviceToken
  }

  func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
    store.send(.appDelegate(.pushRegistrationFailed(error.localizedDescription)))   // simulator, missing entitlement
  }

  // 2. FCM token (fires on every launch and on rotation).
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    guard let fcmToken else { return }
    store.send(.appDelegate(.fcmTokenReceived(fcmToken)))   // reducer uploads via pushClient
  }

  // 3. Foreground presentation.
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
    let userInfo = notification.request.content.userInfo
    Messaging.messaging().appDidReceiveMessage(userInfo)   // only needed with swizzling off
    // Show banners in the foreground except for the thread the user is currently looking at.
    if let threadId = userInfo["thread-id"] as? String, store.state.visibleNoteId == threadId { return [] }
    return [.banner, .list, .sound, .badge]
  }

  // 4. Tap / action → TCA action.
  func userNotificationCenter(_ center: UNUserNotificationCenter,
                              didReceive response: UNNotificationResponse) async {
    let userInfo = response.notification.request.content.userInfo
    Messaging.messaging().appDidReceiveMessage(userInfo)
    guard let link = PushDeepLink(userInfo: userInfo, action: response.actionIdentifier) else { return }
    store.send(.appDelegate(.pushOpened(link)))
  }

  // 5. Silent push (only with the remote-notification background mode).
  func application(_ application: UIApplication,
                   didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
    Messaging.messaging().appDidReceiveMessage(userInfo)
    guard userInfo["type"] as? String == "sync" else { return .noData }
    return await store.withBackgroundSync()   // a helper that sends .backgroundSyncRequested and awaits completion
  }
}
```

`PushDeepLink` is a plain `Equatable` value parsed from `userInfo` (`type`, ids, `actionIdentifier`). Parse in the delegate, decide in the reducer. If the app was launched from a push, the `didReceive` delegate still fires on launch — no need to read `launchOptions`.

## Authorization

Ask at a moment that makes sense (after the first share, not on first launch). Use provisional authorization when the app wants to deliver quietly without a prompt; iOS then shows notifications in Notification Center only, with a "Keep / Turn off" affordance, until the user promotes them.

```swift
@DependencyClient
struct PushClient: Sendable {
  var requestAuthorization: @Sendable (_ provisional: Bool) async throws -> Bool
  var authorizationStatus: @Sendable () async -> UNAuthorizationStatus = { .notDetermined }
  var currentToken: @Sendable () async throws -> String
  var uploadToken: @Sendable (_ token: String) async throws -> Void
  var deleteToken: @Sendable () async throws -> Void
  var setBadge: @Sendable (_ count: Int) async throws -> Void
}

extension PushClient: DependencyKey {
  static let liveValue = PushClient(
    requestAuthorization: { provisional in
      var options: UNAuthorizationOptions = [.alert, .badge, .sound]
      if provisional { options.insert(.provisional) }
      let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
      await UIApplication.shared.registerForRemoteNotifications()   // idempotent; already called at launch
      return granted
    },
    authorizationStatus: { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus },
    currentToken: { try await Messaging.messaging().token() },
    uploadToken: { try await PushRegistrar.shared.upload(token: $0) },   // see token-registry.md
    deleteToken: { try await Messaging.messaging().deleteToken() },
    setBadge: { try await UNUserNotificationCenter.current().setBadgeCount($0) }
  )
}
```

`registerForRemoteNotifications()` does not require authorization — the APNs token and silent pushes work regardless. Authorization only gates visible alerts, sounds, and badges.

## Reducer shape

```swift
@Reducer
struct AppFeature {
  @ObservableState
  struct State: Equatable {
    var visibleNoteId: String?
    var path = StackState<Path.State>()
    var unreadCount = 0
  }
  enum Action {
    case appDelegate(AppDelegate)
    case signedIn(uid: String)
    case path(StackActionOf<Path>)
    enum AppDelegate: Equatable {
      case didFinishLaunching
      case fcmTokenReceived(String)
      case pushRegistrationFailed(String)
      case pushOpened(PushDeepLink)
    }
  }
  @Dependency(\.pushClient) var pushClient

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case let .appDelegate(.fcmTokenReceived(token)):
        return .run { _ in try await pushClient.uploadToken(token) } catch: { _, _ in }  // upload is best-effort; retried on next launch

      case .signedIn:
        // Delegate may have fired before sign-in; re-upload now that there is a uid.
        return .run { _ in try await pushClient.uploadToken(pushClient.currentToken()) } catch: { _, _ in }

      case let .appDelegate(.pushOpened(link)):
        switch link {
        case let .note(id, _):
          state.path.append(.noteDetail(NoteDetailFeature.State(noteId: id)))
        }
        return .none

      case .appDelegate, .path:
        return .none
      }
    }
    .forEach(\.path, action: \.path)
  }
}
```

Navigation modelling follows `tca-pro` → `references/navigation.md`. If the target screen requires data that is not loaded yet, append a state that loads by id — never wait for the whole app to hydrate before handling the deep link.

## Badge management

- The server is the source of truth for the number (`aps.badge = unreadCount`). Every device of the user gets the same value.
- When the user reads items in-app, the client sets the badge locally (`setBadgeCount`) **and** the server recomputes on the next send. Do not `increment` on either side.
- Clear on sign-out: `setBadgeCount(0)` and remove delivered notifications with `UNUserNotificationCenter.current().removeAllDeliveredNotifications()`.
- Do not use `UIApplication.shared.applicationIconBadgeNumber` — deprecated in iOS 17; `setBadgeCount(_:)` is iOS 16+.

## Testing on device

- Simulators cannot receive APNs pushes from FCM. Drag a `.apns` file onto the simulator to test the delegate path locally (`{ "Simulator Target Bundle": "com.doxuto.snaptool", "aps": { "alert": { "title": "x" } }, "type": "note.shared", "noteId": "n1" }`).
- On a physical device, print the FCM token at debug level and use the Firebase console "Send test message" with that token, or a `sendTestPush` callable behind an admin claim (see `patterns.md`).
- Set `-FIRDebugEnabled` in the scheme's launch arguments to see FCM delivery logs.

## Does not exist / common mistakes

- Reading `Messaging.messaging().fcmToken` in `didFinishLaunching` — often `nil`; use the delegate or `token()`.
- Uploading the token before sign-in and never again — the `signedIn` re-upload above is required.
- Calling `Messaging.messaging()` inside a reducer — wrap in `PushClient`.
- Handling deep links by parsing `alert.body` — route on `data` keys only.
- `UNUserNotificationCenter.current().delegate` set after the first notification arrives — set it in `didFinishLaunching`.
- `application(_:didReceiveRemoteNotification:)` without the `remote-notification` background mode — never called in the background.
- `registerForRemoteNotifications()` on a background thread — call it on the main actor (the delegate's methods already are).

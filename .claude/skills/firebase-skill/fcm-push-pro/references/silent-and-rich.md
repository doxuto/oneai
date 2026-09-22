# Silent pushes, rich notifications, Live Activities

Three different mechanisms that share the word "push" and nothing else. Get the type right first, then the payload.

## Background (silent) push

Purpose: wake the app for up to ~30 seconds to sync, without showing anything.

Server rules — all four, always:

```ts
const silent: Message = {
  token,
  data: { type: "sync", collection: "notes" },      // what to do; strings only
  apns: {
    headers: {
      "apns-push-type": "background",               // 1. mandatory
      "apns-priority": "5",                         // 2. must be 5; APNs rejects 10 for background
    },
    payload: { aps: { "content-available": 1 } },   // 3. the wake-up flag
  },
  // 4. no `notification`, no aps.alert, no sound, no badge
};
```

Optional: `"apns-expiration": "0"` if the sync is pointless when late.

What iOS does with it:

- Delivers to `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` (or the async variant) only if the app has the **Remote notifications** background mode (`UIBackgroundModes` contains `remote-notification`).
- Does **not** wake an app the user force-quit from the app switcher. That is by design; do not build anything that depends on it.
- Throttles: budget is roughly a few per hour per app, less in Low Power Mode, and iOS learns from how the app uses the time. A silent push every minute is dropped.
- Gives ~30 s. Call the completion (return the fetch result) as soon as the work is done.
- When the app is in the foreground the same method is called immediately.

```swift
// AppDelegate
func application(_ application: UIApplication,
                 didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
  // If method swizzling is disabled (FirebaseAppDelegateProxyEnabled = NO), forward for delivery analytics:
  Messaging.messaging().appDidReceiveMessage(userInfo)
  guard userInfo["type"] as? String == "sync" else { return .noData }
  await syncClient.pullChanges()          // a @DependencyClient; bounded by ~30 s
  return .newData
}
```

Design guidance:

- Prefer a Firestore snapshot listener for live data while the app runs; use a silent push only for "the app is backgrounded and should prefetch before the user comes back".
- Do not use a silent push to update the badge — a badge-only push (`aps.badge` without `content-available`) does that without a wake-up and without throttling.
- Do not combine a silent push with an alert in the same message to "wake the app and show something". The result is unreliable on both counts. Send two messages, or let the NSE do the work (below).

## Rich notifications (`mutable-content` + Notification Service Extension)

Purpose: modify a visible notification before it is shown — attach an image/audio/video, decrypt content, rewrite text from local data, or fetch the full body by id (keeps the payload under 4 KB).

Server side:

```ts
const rich: Message = {
  token,
  notification: { title: "Minh shared a note", body: "Q3 planning draft" },
  data: { type: "note.shared", noteId },
  apns: {
    headers: { "apns-push-type": "alert", "apns-priority": "10" },
    payload: { aps: { "mutable-content": 1, sound: "default", category: "NOTE_SHARED", "thread-id": noteId } },
    fcmOptions: { imageUrl: "https://…/thumb.jpg" },   // becomes fcm_options.image in the APNs payload
  },
};
```

`mutable-content` only runs the extension for a notification that will be displayed — it needs an alert. If the NSE fails or times out, iOS shows the original alert unchanged, so the server payload must be presentable on its own.

iOS side — a Notification Service Extension target in the same Xcode project, with the `FirebaseMessaging` package linked to the extension:

```swift
import UserNotifications
import FirebaseMessaging

final class NotificationService: UNNotificationServiceExtension {
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var bestAttempt: UNMutableNotificationContent?

  override func didReceive(_ request: UNNotificationRequest,
                           withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
    self.contentHandler = contentHandler
    bestAttempt = (request.content.mutableCopy() as? UNMutableNotificationContent)
    guard let bestAttempt else { return contentHandler(request.content) }

    // Local rewrite example: append the note title from the shared app-group store.
    if let noteId = bestAttempt.userInfo["noteId"] as? String,
       let title = SharedNoteCache(appGroup: "group.com.doxuto.snaptool").title(for: noteId) {
      bestAttempt.subtitle = title
    }

    // Downloads fcm_options.image and attaches it, then calls the handler. ~30 s budget in total.
    Messaging.serviceExtension().populateNotificationContent(bestAttempt, withContentHandler: contentHandler)
  }

  override func serviceExtensionTimeWillExpire() {
    if let contentHandler, let bestAttempt { contentHandler(bestAttempt) }   // ship what you have
  }
}
```

Rules for the extension:

- It runs in a separate process with its own sandbox. It cannot read the app's `UserDefaults` or Keychain unless both use an app group / shared keychain access group.
- It can do network calls (Firestore via the Admin-less client SDK is possible but heavy; prefer a small `URLSession` request to a callable/HTTP function or a pre-signed URL).
- Keep the memory footprint small (the extension has a low limit — a few tens of MB). Resize images server-side before pointing `imageUrl` at them.
- `populateNotificationContent` is the FirebaseMessaging helper for `fcm_options.image`; if you attach your own media, download to a temp file and use `UNNotificationAttachment(identifier:url:options:)`.

Categories with actions are registered in the app on launch, not in the NSE:

```swift
let open = UNNotificationAction(identifier: "OPEN", title: "Open", options: [.foreground])
let mute = UNNotificationAction(identifier: "MUTE_THREAD", title: "Mute", options: [.destructive])
let category = UNNotificationCategory(identifier: "NOTE_SHARED", actions: [open, mute], intentIdentifiers: [])
UNUserNotificationCenter.current().setNotificationCategories([category])
```

`response.actionIdentifier` in `didReceive` tells you which action fired (`UNNotificationDefaultActionIdentifier` for a plain tap).

## Live Activities — a different token, a different push type

Live Activities (Dynamic Island, Lock Screen) are updated through APNs with `apns-push-type: liveactivity`, but they are addressed by an **ActivityKit push token**, not the device's APNs/FCM registration token. Each activity instance has its own token, obtained on the client:

```swift
let activity = try Activity<DeliveryAttributes>.request(
  attributes: attrs, content: .init(state: initial, staleDate: nil), pushType: .token)
Task {
  for await tokenData in activity.pushTokenUpdates {
    let hex = tokenData.map { String(format: "%02x", $0) }.joined()
    try await api.registerLiveActivityToken(activityId: activity.id, token: hex)   // users/{uid}/liveActivities/{id}
  }
}
```

Server side, the APNs request is:

- topic `<bundleId>.push-type.liveactivity`, header `apns-push-type: liveactivity`, `apns-priority: 10` (or 5 for non-urgent),
- payload `aps: { timestamp: unixSeconds, event: "update" | "end", "content-state": { … matches ContentState … }, "stale-date"?: unix, "dismissal-date"?: unix, alert?: { title, body } }`,
- iOS 17.2+ push-to-start uses a separate `pushToStartTokenUpdates` token and `event: "start"` with `attributes-type` and `attributes`.

Through FCM: the FCM HTTP v1 `ApnsConfig` has a `live_activity_token` field for this purpose; whether the firebase-admin Node `ApnsConfig` type exposes it as `liveActivityToken` depends on the exact 13.x version — **verify against firebase docs** before relying on it. If it is not available, send directly to APNs over HTTP/2 with a JWT signed by the same .p8 key (`jose` for the token, Node `http2` for the request — `fetch` does not speak HTTP/2):

```ts
import * as http2 from "node:http2";
import { SignJWT, importPKCS8 } from "jose";

async function apnsJwt(keyId: string, teamId: string, p8: string): Promise<string> {
  const key = await importPKCS8(p8, "ES256");
  return new SignJWT({}).setProtectedHeader({ alg: "ES256", kid: keyId }).setIssuer(teamId).setIssuedAt().sign(key);
}

export async function sendLiveActivityUpdate(opts: {
  token: string; bundleId: string; jwt: string; contentState: Record<string, unknown>; event?: "update" | "end";
}): Promise<number> {
  const client = http2.connect("https://api.push.apple.com");   // sandbox: api.sandbox.push.apple.com
  const body = JSON.stringify({ aps: { timestamp: Math.floor(Date.now() / 1000), event: opts.event ?? "update", "content-state": opts.contentState } });
  return new Promise((resolve, reject) => {
    const req = client.request({
      ":method": "POST", ":path": `/3/device/${opts.token}`,
      authorization: `bearer ${opts.jwt}`, "apns-topic": `${opts.bundleId}.push-type.liveactivity`,
      "apns-push-type": "liveactivity", "apns-priority": "10", "content-type": "application/json",
    });
    req.on("response", (h) => resolve(Number(h[":status"])));
    req.on("error", reject);
    req.end(body);
    req.on("close", () => client.close());
  });
}
```

Store the .p8 contents, key id, and team id as secrets (`defineSecret`). Cache the JWT for up to an hour (APNs rejects tokens older than 60 minutes and more than one refresh per 20 minutes).

Do not put Live Activity tokens in `users/{uid}/devices` — they are per activity, short-lived, and must be removed when `activity.activityStateUpdates` reports `.ended` or `.dismissed`.

## Does not exist / common mistakes

- `"content-available": 1` with `"apns-priority": "10"` — APNs returns 400 `TopicDisallowed`/`BadPriority` or silently downgrades; use `"5"`.
- Expecting a silent push to relaunch a force-quit app — it never does.
- `Messaging.messaging().apnsToken` for Live Activities — wrong token type; use `activity.pushTokenUpdates`.
- `UNNotificationServiceExtension` without `mutable-content: 1` in the payload — it never runs.
- `mutable-content` on a data-only message — ignored; there is nothing to display.
- `Messaging.serviceExtension()` in the main app target — it is for the extension. In the app the image is not needed; the notification already shows it.
- Relying on `notification.imageUrl` alone for iOS images — needs the NSE path above.
- Registering `UNNotificationCategory` inside the extension — categories are app-level; register them at launch in the app.

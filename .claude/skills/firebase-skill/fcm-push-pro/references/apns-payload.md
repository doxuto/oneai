# APNs payload through FCM

FCM HTTP v1 forwards the `apns` block to APNs mostly verbatim. What iOS does with a push is decided by `apns.headers` and `apns.payload.aps`; the top-level `notification` field is only a cross-platform shorthand that FCM translates into `aps.alert`.

## Message shape (firebase-admin `Message`)

```ts
import type { Message } from "firebase-admin/messaging";

const msg: Message = {
  token,                                   // exactly one of token | topic | condition
  notification: { title, body, imageUrl }, // optional shorthand; FCM maps it to aps.alert (+ fcm_options.image)
  data: { type: "note.shared", noteId },   // string → string only
  apns: {
    headers: { /* APNs request headers, all string values */ },
    payload: {
      aps: { /* see table */ },
      // any other top-level keys here are custom payload keys visible in userInfo
    },
    fcmOptions: { imageUrl, analyticsLabel },
  },
  fcmOptions: { analyticsLabel: "note_shared" },
};
```

Rules:

- `data` values must be strings. `data: { count: 3 }` fails validation; write `String(count)`.
- Reserved `data` keys: `from`, `notification`, `message_type`, anything starting with `google.` or `gcm.`. Do not use them.
- `apns.payload.aps` accepts the typed camelCase fields of the SDK's `Aps` interface (`contentAvailable: true`, `mutableContent: true`, `threadId`) **or** the raw APNs keys (`"content-available": 1`, `"mutable-content": 1`, `"thread-id"`). The SDK converts the typed ones and passes raw keys through unchanged. Pick one style per codebase; this bundle uses the raw keys so the payload reads like Apple's documentation.
- Keys Apple added later (`interruption-level`, `relevance-score`, `target-content-id`, `filter-criteria`) have no typed field — write them as raw keys.

## `aps` key table

| Key | Type | Effect | Notes |
|---|---|---|---|
| `alert` | string or object | Visible notification | Object form below. A bare string becomes the body. |
| `alert.title` | string | Bold first line | |
| `alert.subtitle` | string | Second line | |
| `alert.body` | string | Message text | |
| `alert.title-loc-key` / `title-loc-args` | string / string[] | Localised title from the app's `Localizable.strings` | See localisation in `sending.md`. |
| `alert.subtitle-loc-key` / `subtitle-loc-args` | | Localised subtitle | |
| `alert.loc-key` / `loc-args` | | Localised body | |
| `alert.launch-image` | string | Launch image when opened from the push | Rarely used. |
| `sound` | string or object | `"default"`, or a file name in the bundle (≤ 30 s, aiff/wav/caf) | Omit for silent. |
| `sound` (critical) | `{ critical: 1, name: "alarm.caf", volume: 0.8 }` | Critical alert — bypasses Focus and mute | Requires the `com.apple.developer.usernotifications.critical-alerts` entitlement granted by Apple and `.criticalAlert` authorization. |
| `badge` | number | Sets the app icon badge to exactly this value | `0` clears. Not relative. |
| `category` | string | Matches a registered `UNNotificationCategory` for action buttons | Register categories on launch. |
| `thread-id` | string | Groups notifications in Notification Center | Use the conversation/note id. |
| `content-available` | `1` | Wakes the app in the background for `didReceiveRemoteNotification` | Silent push. Must not combine with alert/sound/badge in the same message if you want reliable background delivery; see `silent-and-rich.md`. |
| `mutable-content` | `1` | Runs the Notification Service Extension before display | Rich media, decryption, local rewriting. Requires an alert. |
| `interruption-level` | `"passive"` / `"active"` / `"time-sensitive"` / `"critical"` | iOS 15+ Focus behaviour | `time-sensitive` needs the Time Sensitive Notifications capability. `critical` needs the critical entitlement. |
| `relevance-score` | number 0–1 | Ordering inside the notification summary | |
| `target-content-id` | string | Which scene to open (multi-window apps) | iOS 13+. |
| `filter-criteria` | string | Focus filter matching | iOS 16+. |
| `stale-date`, `content-state`, `event`, `timestamp` | | Live Activity updates | Only with push-type `liveactivity`; see `silent-and-rich.md`. |

## `apns.headers` table

| Header | Values | Notes |
|---|---|---|
| `apns-push-type` | `alert`, `background`, `location`, `voip`, `complication`, `fileprovider`, `mdm`, `liveactivity`, `pushtotalk` | Required by APNs on iOS 13+. FCM fills `alert` when a `notification` is present, but set it explicitly. `background` is mandatory for silent pushes. |
| `apns-priority` | `"10"` immediate, `"5"` power-considerate, `"1"` lowest (iOS 15+) | Silent pushes must be `"5"`. `"10"` with `background` type is rejected by APNs. |
| `apns-expiration` | Unix epoch seconds as string; `"0"` = try once, never store | Use for time-limited content (OTP, "your ride is here"). Default: APNs stores for a while and delivers on reconnect. |
| `apns-collapse-id` | ≤ 64 bytes | Newer push with the same id replaces the older one on the device. Use for "N new messages" style updates. |
| `apns-topic` | bundle id | FCM sets it from the APNs key configuration. Do not set it yourself unless targeting a Live Activity or another push type that needs a suffixed topic — then verify against firebase docs whether FCM allows overriding it. |
| `apns-id` | UUID | Optional; FCM assigns its own id. |

All header values are strings, including the numbers.

## Notification message vs data-only message

| | Notification message | Data-only message |
|---|---|---|
| Has `notification` or `aps.alert` | yes | no |
| App backgrounded/killed | OS shows it; app not woken (unless `content-available`) | Nothing shown; app woken only if `content-available: 1` + `background` push-type |
| App foregrounded | `willPresent` delegate decides; `didReceiveRemoteNotification` called | `didReceiveRemoteNotification` called |
| User taps | `didReceive response` with `userInfo` | n/a (nothing to tap) |
| Use for | anything the user should see | sync triggers, cache invalidation, badge-only updates |

A badge-only update is a data-only message with `aps.badge` set and no alert — the OS applies the badge without showing anything, and does not need `content-available` for that. Do not add `content-available` unless you also want the app woken.

FCM's top-level `notification` is convenient but hides the mapping. For anything beyond title/body, write `aps.alert` yourself and leave `notification` out — otherwise two sources of truth drift.

## Size limit

APNs rejects payloads larger than **4 KB (4096 bytes)** for regular pushes (VoIP: 5 KB). FCM enforces the same ceiling for `notification` + `data`. The size is of the JSON APNs receives, including keys. Practical guidance:

- Keep `data` to ids and a `type`. Fetch the body from Firestore on the client or in the NSE.
- Never put base64 images, full note text, or long arrays in `data`.
- FCM returns `messaging/payload-size-limit-exceeded` when you cross the line; treat it as a bug, not a retryable error.

## Complete payload examples

Visible, grouped, with actions and rich media:

```ts
apns: {
  headers: { "apns-push-type": "alert", "apns-priority": "10", "apns-collapse-id": `note-${noteId}` },
  payload: {
    aps: {
      alert: { title: "Minh shared a note", subtitle: "Project Alpha", body: "Q3 planning draft" },
      sound: "default",
      badge: unreadCount,
      category: "NOTE_SHARED",
      "thread-id": noteId,
      "mutable-content": 1,
      "interruption-level": "active",
      "relevance-score": 0.7,
    },
  },
  fcmOptions: { imageUrl: thumbnailUrl },   // NSE downloads it via Messaging.serviceExtension()
}
```

Silent sync trigger:

```ts
apns: {
  headers: { "apns-push-type": "background", "apns-priority": "5" },
  payload: { aps: { "content-available": 1 } },
},
data: { type: "sync", collection: "notes" },
```

Badge-only:

```ts
apns: {
  headers: { "apns-push-type": "alert", "apns-priority": "5" },
  payload: { aps: { badge: 0 } },
},
```

Localised on-device (app ships the strings):

```ts
aps: {
  alert: {
    "title-loc-key": "PUSH_NOTE_SHARED_TITLE",
    "title-loc-args": [fromName],
    "loc-key": "PUSH_NOTE_SHARED_BODY",
    "loc-args": [noteTitle],
  },
  sound: "default",
},
```

## Reading the payload on iOS

```swift
// userInfo is the whole APNs payload: aps + custom keys (FCM puts `data` at top level).
func userNotificationCenter(_ center: UNUserNotificationCenter,
                            didReceive response: UNNotificationResponse) async {
  let userInfo = response.notification.request.content.userInfo
  guard let type = userInfo["type"] as? String else { return }
  let noteId = userInfo["noteId"] as? String
  // route to a TCA action — see ios-client.md
}
```

`data` keys arrive at the top level of `userInfo`, next to `aps` and FCM's own `gcm.message_id` / `google.c.*` keys. Do not name a data key `aps`.

## Does not exist / common mistakes

- `notification.badge` — not a field of FCM `Notification`. Badge lives in `aps.badge`.
- `apns.payload.aps.badge: "3"` — must be a number.
- `data: { payload: { … } }` nested objects — validation fails; JSON-encode into a string if you must.
- `"content-available": true` as a raw key — APNs wants the integer `1`. (The typed `contentAvailable: true` is converted correctly.)
- `apns-priority: 10` as a number — header values are strings.
- `"apns-push-type": "silent"` — not a push type. Use `background`.
- Sending `sound` with a silent push — turns it into a visible push in APNs's eyes, subject to throttling and shown as an empty banner on some versions.
- `mutable-content` without an alert — the NSE only runs for notifications that will be displayed.
- Assuming `notification.imageUrl` shows an image on iOS without an NSE — it does not; iOS needs `mutable-content: 1` plus the FirebaseMessaging extension helper (or your own download) in the extension.

---
name: fcm-push-pro
description: Writes, reviews, and refactors push-notification code that sends from Firebase Cloud Functions (2nd gen, TypeScript) to an iOS app through FCM and APNs, including the token registry in Firestore and the Swift receiving side. Use when reading, writing, or reviewing code that uses FCM, getMessaging, send, sendEach, sendEachForMulticast, subscribeToTopic, topics or conditions, APNs, an apns payload, aps keys, mutable-content, content-available, silent push, badge, a Notification Service Extension, device tokens or registration tokens, or the iOS side with Messaging.messaging(), apnsToken, didReceiveRegistrationToken, UNUserNotificationCenter, or when the user mentions push notifications, remote notifications, or notification deep links.
license: MIT
metadata:
  author: doxuto
  version: "1.0"
  targets: "firebase-functions 6.x (v2), firebase-admin 13.x, Node 22, Firebase iOS SDK 12.x"
---

Write and review FCM/APNs push code for correct payloads, a healthy token registry, resilient sending, and a clean iOS receiving path. Report only genuine problems — do not nitpick or invent issues.

## Core principles

1. **The token registry is the product.** A push system is only as good as its list of live tokens. One document per installation, timestamped on every launch, pruned on error and on age.
2. **APNs decides what the user sees, not FCM.** `notification` is a convenience; the `apns.payload.aps` block is what iOS actually reads. Write it explicitly for anything beyond title/body.
3. **Silent and visible are different products.** A background push has `content-available: 1`, priority `5`, push-type `background`, and no alert. Mixing the two produces pushes that neither wake the app nor show.
4. **Sending is batched, bounded, and idempotent.** `sendEachForMulticast` in chunks of 500, retries only on transient errors, and a dedupe key so an at-least-once trigger never sends twice.
5. **Data in `data`, presentation in `aps`.** The iOS app routes on `data.type` and `data.*` ids; it never parses the alert text.
6. **The client is thin.** iOS registers, uploads the token, presents, and turns a tap into a TCA action. Business logic lives in the reducer (`tca-pro`), not in the AppDelegate.

## Review process

1. Check the Firestore token schema, upload/refresh path, pruning, and sign-out handling using `references/token-registry.md`.
2. Check every `apns.payload.aps` block and `apns.headers` against `references/apns-payload.md`.
3. Check the send call — API choice, chunking, error handling, retries, logging — using `references/sending.md`.
4. Check background pushes, rich media, and Live Activity claims using `references/silent-and-rich.md`.
5. Check the Swift registration, delegate, foreground presentation, and deep-link path using `references/ios-client.md`.
6. Check trigger-driven, scheduled digest, preference, and dedupe logic using `references/patterns.md`.

If doing a partial review, load only the relevant reference files.

## Core instructions

- Import from `firebase-admin/messaging` (`getMessaging`) only. `sendMulticast`, `sendAll`, and `sendToDevice` are removed in firebase-admin 13 — never write them.
- Store tokens at `users/{uid}/devices/{installationId}` with `{ token, platform: "ios", appVersion, locale, updatedAt }`. Never store tokens in an array on the user document.
- Update `updatedAt` on every app launch and every `didReceiveRegistrationToken`. Prune documents with `updatedAt` older than 60 days in a scheduled job.
- On `messaging/registration-token-not-registered` or `messaging/invalid-registration-token`, delete that device document in the same function run. Do not retry those.
- Retry only `messaging/server-unavailable`, `messaging/internal-error`, `messaging/unknown-error`, and rate-limit errors, with exponential backoff and a cap. Everything else is a bug or a dead token.
- `data` values are strings. Serialise numbers and booleans yourself; never pass nested objects.
- Every visible push sets `apns.headers["apns-push-type"] = "alert"` and `"apns-priority" = "10"`. Every silent push sets `"background"` and `"5"`, `aps["content-available"] = 1`, and no `alert`, `sound`, or `badge`.
- `badge` is a number, not a string; FCM `notification.badge` does not exist — set `aps.badge`.
- Chunk `sendEachForMulticast` at 500 tokens. Chunk `subscribeToTopic` at 1000 tokens.
- Keep the total payload under 4 KB (APNs limit). Put large content behind an id and fetch it on the client or in the Notification Service Extension.
- Any push produced by a Firestore trigger must be idempotent: write a `notifications/{eventId}` marker with `ref.create()` before sending; skip on `ALREADY_EXISTS`.
- Respect the per-user preference document and quiet hours before every send, not only for digests.
- On the iOS side, set `Messaging.messaging().apnsToken` before reading or uploading the FCM token; `apnsToken` is set in `didRegisterForRemoteNotificationsWithDeviceToken`.
- Never call `Messaging.messaging()` or `UNUserNotificationCenter` from a reducer — wrap them in a `@DependencyClient` (see `tca-pro` → `references/dependencies.md`).
- The APNs auth key (.p8) must be uploaded in Firebase console → Cloud Messaging. Without it iOS sends succeed at FCM and never arrive; check this before debugging payloads.

## Canonical example

A Firestore trigger that notifies a user when a note is shared with them, deduped by event id, chunked at 500, and pruning dead tokens.

```ts
// functions/src/push/onNoteShared.ts
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { getFirestore, FieldValue } from "firebase-admin/firestore";
import { getMessaging, type MulticastMessage } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import { initializeApp, getApps } from "firebase-admin/app";

if (getApps().length === 0) initializeApp();
const db = getFirestore();

interface DeviceDoc {
  token: string;
  platform: "ios";
  locale?: string;
  updatedAt: FirebaseFirestore.Timestamp;
}

const DEAD_TOKEN_CODES = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

export const onNoteShared = onDocumentCreated(
  { document: "users/{uid}/inbox/{shareId}", region: "asia-southeast1" },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const { uid, shareId } = event.params;
    const share = snap.data() as { noteId: string; fromName: string; title: string };

    // 1. Idempotency: at-least-once delivery means this handler can run twice.
    const marker = db.doc(`users/${uid}/notifications/${event.id}`);
    try {
      await marker.create({ type: "note.shared", shareId, createdAt: FieldValue.serverTimestamp() });
    } catch (e: unknown) {
      if ((e as { code?: number }).code === 6) return;   // ALREADY_EXISTS
      throw e;
    }

    // 2. Preferences gate.
    const prefs = (await db.doc(`users/${uid}/settings/notifications`).get()).data();
    if (prefs?.noteShared === false) return;

    // 3. Live tokens only.
    const devices = await db.collection(`users/${uid}/devices`).where("platform", "==", "ios").get();
    const docs = devices.docs;
    if (docs.length === 0) return;

    const base: Omit<MulticastMessage, "tokens"> = {
      notification: { title: `${share.fromName} shared a note`, body: share.title },
      data: { type: "note.shared", noteId: share.noteId, shareId },
      apns: {
        headers: { "apns-priority": "10", "apns-push-type": "alert", "apns-collapse-id": `share-${share.noteId}` },
        payload: {
          aps: {
            sound: "default",
            category: "NOTE_SHARED",
            "thread-id": share.noteId,
            "mutable-content": 1,
          },
        },
      },
    };

    // 4. Send in chunks of 500, delete dead tokens, log the rest.
    const stale: FirebaseFirestore.DocumentReference[] = [];
    for (let i = 0; i < docs.length; i += 500) {
      const chunk = docs.slice(i, i + 500);
      const res = await getMessaging().sendEachForMulticast({
        ...base,
        tokens: chunk.map((d) => (d.data() as DeviceDoc).token),
      });
      res.responses.forEach((r, idx) => {
        if (r.success) return;
        const code = r.error?.code ?? "unknown";
        if (DEAD_TOKEN_CODES.has(code)) stale.push(chunk[idx].ref);
        else logger.warn("push failed", { uid, code, message: r.error?.message });
      });
      logger.info("push sent", { uid, type: "note.shared", success: res.successCount, failure: res.failureCount });
    }
    if (stale.length > 0) {
      const batch = db.batch();
      stale.forEach((ref) => batch.delete(ref));
      await batch.commit();
    }
  }
);
```

The iOS half, reduced to the parts the server depends on (full version in `references/ios-client.md`):

```swift
// AppDelegate.swift
final class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate {
  func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    Messaging.messaging().apnsToken = deviceToken       // must happen before the FCM token is used
  }

  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    guard let fcmToken else { return }
    Task { try await PushRegistrar.shared.upload(token: fcmToken) }   // writes users/{uid}/devices/{installationId}
  }
}
```

## Output format

If the user asks for a review, organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated.
3. Show a brief before/after code fix.

Skip files with no issues. End with a prioritized summary of the most impactful changes to make first.

If the user asks you to write or improve code, follow the same rules but make the changes directly instead of returning a findings report.

Example output:

### sendDigest.ts

**Line 31: Silent push carries an alert and priority 10 — iOS treats it as a visible push and may throttle it.**

```ts
// Before
apns: { headers: { "apns-priority": "10" }, payload: { aps: { "content-available": 1, alert: { title: "Sync" } } } }

// After
apns: { headers: { "apns-priority": "5", "apns-push-type": "background" }, payload: { aps: { "content-available": 1 } } }
```

**Line 58: Dead tokens are logged but never deleted — the registry grows and every send pays for them.**

```ts
// Before
if (!r.success) logger.warn("failed", r.error?.code);

// After
if (!r.success && DEAD_TOKEN_CODES.has(r.error?.code ?? "")) stale.push(chunk[idx].ref);
```

### Summary

1. **Delivery (high):** The mixed silent/alert payload on line 31 is dropped or throttled by iOS; split it into two messages.
2. **Registry health (medium):** Dead tokens on line 58 must be deleted in the same run.

End of example.

## References

- `references/token-registry.md` — Firestore schema `users/{uid}/devices/{installationId}`, upload on launch and on refresh, timestamps, the scheduled prune job (> 60 days), deletion on error codes, multi-device users, and sign-out handling.
- `references/apns-payload.md` — the full `aps` key table (alert, sound incl. critical, badge, category, thread-id, mutable-content, content-available, interruption-level, relevance-score, target-content-id), `apns.headers` (priority, push-type, expiration, collapse-id), notification vs data-only messages, and the 4 KB limit.
- `references/sending.md` — `send` vs `sendEach` vs `sendEachForMulticast`, chunking at 500, topics and conditions, dry run, the error-code table, retry with backoff, structured logging, and server-side vs `loc-key` localisation.
- `references/silent-and-rich.md` — background push rules, rich media with `mutable-content` and a Notification Service Extension, and why Live Activities use ActivityKit push tokens rather than the FCM device token.
- `references/ios-client.md` — AppDelegate and SwiftUI app setup, `UNUserNotificationCenter`, provisional authorization, `apnsToken` ordering, delegate methods, foreground presentation, deep link to a TCA action, and badge management.
- `references/patterns.md` — notify on a Firestore trigger, batched digests with `onSchedule`, per-user preference document and quiet hours, dedupe, and testing pushes with dry run and the Firebase console.

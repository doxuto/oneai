# Patterns

Reusable shapes for the pushes an iOS app actually sends. Every pattern below assumes the shared helpers `sendToTokens` (from `sending.md`) and the `users/{uid}/devices` registry (from `token-registry.md`).

## Shared module: `push/core.ts`

```ts
import { getFirestore, FieldValue, Timestamp } from "firebase-admin/firestore";
import { getMessaging, type MulticastMessage } from "firebase-admin/messaging";
import { logger } from "firebase-functions";

const db = getFirestore();

export interface Prefs {
  enabled: boolean;                       // master switch
  kinds: Record<string, boolean>;         // "note.shared": true
  quietHours?: { start: string; end: string };   // "22:00" – "07:00", in the device's timeZone
}

export async function loadPrefs(uid: string): Promise<Prefs> {
  const snap = await db.doc(`users/${uid}/settings/notifications`).get();
  return { enabled: true, kinds: {}, ...(snap.data() as Partial<Prefs> | undefined) };
}

export function isQuiet(prefs: Prefs, timeZone: string, now = new Date()): boolean {
  if (!prefs.quietHours) return false;
  const hm = new Intl.DateTimeFormat("en-GB", { timeZone, hour: "2-digit", minute: "2-digit", hour12: false }).format(now);
  const { start, end } = prefs.quietHours;
  return start <= end ? hm >= start && hm < end : hm >= start || hm < end;   // handles wrap past midnight
}

/** Idempotency marker. Returns false if this event was already handled. */
export async function claimEvent(uid: string, eventId: string, meta: Record<string, string>): Promise<boolean> {
  try {
    await db.doc(`users/${uid}/notifications/${eventId}`).create({ ...meta, createdAt: FieldValue.serverTimestamp(),
      expiresAt: Timestamp.fromMillis(Date.now() + 30 * 86_400_000) });   // TTL policy on expiresAt
    return true;
  } catch (e: unknown) {
    if ((e as { code?: number }).code === 6) return false;   // ALREADY_EXISTS
    throw e;
  }
}

/** Sends `base` to every live iOS device of `uid` that is not in quiet hours; deletes dead tokens. */
export async function notifyUser(uid: string, kind: string, base: Omit<MulticastMessage, "tokens">) {
  const prefs = await loadPrefs(uid);
  if (!prefs.enabled || prefs.kinds[kind] === false) return { skipped: "prefs" as const };
  const devices = await db.collection(`users/${uid}/devices`).where("platform", "==", "ios").get();
  const eligible = devices.docs.filter((d) => !isQuiet(prefs, (d.get("timeZone") as string | undefined) ?? "UTC"));
  if (eligible.length === 0) return { skipped: "quiet-or-none" as const };
  const tokens = eligible.map((d) => d.get("token") as string);
  const res = await sendToTokens({ ...base, fcmOptions: { analyticsLabel: kind.replace(".", "_") } }, tokens);
  if (res.dead.length) {
    const batch = db.batch();
    eligible.filter((d) => res.dead.includes(d.get("token"))).forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
  logger.info("notifyUser", { uid, kind, tokens: tokens.length, ...res, dead: res.dead.length, retryable: res.retryable.length });
  return res;
}
```

Quiet hours: a push suppressed during quiet hours is **dropped**, not queued, unless the kind is one the digest covers (below). Deferring individual pushes needs a task queue with `scheduleDelaySeconds` and a re-check of quiet hours at dispatch — only build that if the product needs it.

## 1. Notify on a Firestore trigger

Event: a share document is written into the recipient's inbox (see the canonical example in `SKILL.md` for the full function). The shape is always the same:

1. `if (!event.data) return;`
2. `claimEvent(uid, event.id, …)` — skip if already handled.
3. Load what the message needs (one or two reads, no fan-out reads).
4. `notifyUser(uid, "note.shared", { notification, data, apns })`.

Guard against self-notification (the actor is also the recipient) and against trigger loops: a trigger on `users/{uid}/notes/{noteId}` that writes `lastNotifiedAt` into the same note re-fires; write markers into a different collection (`notifications`) or compare `before`/`after` in `onDocumentUpdated`.

For "comment added to a note with N collaborators", do not loop `notifyUser` inside the trigger when N can be large; enqueue one task per recipient:

```ts
import { getFunctions } from "firebase-admin/functions";
import { onTaskDispatched } from "firebase-functions/v2/tasks";

export const notifyRecipient = onTaskDispatched(
  { retryConfig: { maxAttempts: 3, minBackoffSeconds: 10 }, rateLimits: { maxConcurrentDispatches: 20 }, region: "asia-southeast1" },
  async (req) => {
    const { uid, kind, eventId, message } = req.data as { uid: string; kind: string; eventId: string; message: Omit<MulticastMessage, "tokens"> };
    if (!(await claimEvent(uid, eventId, { kind }))) return;
    await notifyUser(uid, kind, message);
  }
);

// inside the trigger:
const queue = getFunctions().taskQueue("notifyRecipient");
await Promise.all(recipients.map((uid) => queue.enqueue({ uid, kind: "note.commented", eventId: `${event.id}-${uid}`, message })));
```

## 2. Batched digest with `onSchedule`

For low-urgency kinds (likes, "3 people viewed your note"), accumulate and send once per day per user in their local morning.

Accumulate: the trigger writes `users/{uid}/digest/pending` with `FieldValue.arrayUnion({ kind, noteId, at })` (bounded — cap at ~50 entries by checking length first) or `FieldValue.increment` counters per kind. Do not push.

Send: an hourly job selects users whose local time is 08:00 this hour.

```ts
import { onSchedule } from "firebase-functions/v2/scheduler";

export const sendDigests = onSchedule(
  { schedule: "0 * * * *", timeZone: "UTC", region: "asia-southeast1", timeoutSeconds: 540, memory: "512MiB" },
  async () => {
    const nowUtcHour = new Date().getUTCHours();
    // users/{uid}.digestUtcHour is maintained by the client (08:00 local → UTC hour) on every launch,
    // so this query needs no per-user timezone math and a single index.
    const users = await db.collection("users").where("digestUtcHour", "==", nowUtcHour).select().get();
    for (const u of users.docs) {
      const pendingRef = db.doc(`users/${u.id}/digest/pending`);
      const pending = await pendingRef.get();
      if (!pending.exists) continue;
      const items = (pending.get("items") as Array<{ kind: string; noteId: string }> | undefined) ?? [];
      if (items.length === 0) continue;
      await notifyUser(u.id, "digest", {
        notification: { title: "While you were away", body: summarize(items) },
        data: { type: "digest", count: String(items.length) },
        apns: { headers: { "apns-push-type": "alert", "apns-priority": "5", "apns-collapse-id": "digest" },
                payload: { aps: { sound: "default", "thread-id": "digest", "relevance-score": 0.3 } } },
      });
      await pendingRef.delete();   // reset after send; a retry of the whole job re-sends only users still pending
    }
  }
);
```

Keep the job under `timeoutSeconds`; if the user count grows past a few thousand per hour, have the schedule enqueue one task per user instead of looping.

## 3. Per-user preferences

Document: `users/{uid}/settings/notifications` (the `Prefs` shape above). The client writes it directly under rules that whitelist keys:

```
match /users/{uid}/settings/notifications {
  allow read, write: if isOwner(uid)
    && request.resource.data.keys().hasOnly(['enabled','kinds','quietHours']);
}
```

On the iOS side this is a `@Shared` / Firestore-backed settings feature (`tca-pro` → `references/shared-state.md`). Mirror the `kinds` keys as an enum in Swift so the server and client cannot drift:

```swift
enum PushKind: String, CaseIterable, Codable { case noteShared = "note.shared", noteCommented = "note.commented", digest }
```

When the user disables a kind, nothing else changes server-side — `notifyUser` reads the doc on every send. Cache nothing across invocations.

## 4. Dedupe

Three layers, from cheapest to strongest:

1. **Event id marker** — `claimEvent` with `ref.create()`. Handles at-least-once trigger delivery.
2. **Collapse id** — `apns-collapse-id` per subject (`note-${noteId}`) so a burst of edits shows one banner.
3. **Rate window** — for kinds that can spike (comments), store `lastSentAt[kind:subject]` on the marker or the user doc and skip if within N minutes:

```ts
const key = `note.commented:${noteId}`;
const stateRef = db.doc(`users/${uid}/pushState/${encodeURIComponent(key)}`);
const shouldSend = await db.runTransaction(async (tx) => {
  const s = await tx.get(stateRef);
  const last = (s.get("lastSentAt") as Timestamp | undefined)?.toMillis() ?? 0;
  if (Date.now() - last < 10 * 60_000) return false;
  tx.set(stateRef, { lastSentAt: FieldValue.serverTimestamp() });
  return true;
});
```

## 5. Testing pushes

- **Dry run** in tests: `getMessaging().sendEachForMulticast(msg, true)` validates payload and token with FCM without delivering. There is no FCM emulator; the call hits the real service, so run these against the dev project only.
- **Unit tests** with `firebase-functions-test`: wrap the trigger, feed a `makeDocumentSnapshot`, and mock `firebase-admin/messaging` (vitest `vi.mock`) to assert the payload — the shape is what you own; delivery is Firebase's.
- **Firebase console** → Messaging → "New campaign" → "Send test message" with a device's FCM token: verifies APNs key configuration end to end. Do this first when "nothing arrives".
- **Admin callable** for engineers:

```ts
export const sendTestPush = onCall({ region: "asia-southeast1", enforceAppCheck: true }, async (request) => {
  if (request.auth?.token.role !== "admin") throw new HttpsError("permission-denied", "admin only");
  const { uid, dryRun } = z.object({ uid: z.string(), dryRun: z.boolean().default(true) }).parse(request.data);
  const devices = await db.collection(`users/${uid}/devices`).get();
  const res = await getMessaging().sendEachForMulticast({
    tokens: devices.docs.map((d) => d.get("token") as string),
    notification: { title: "Test", body: new Date().toISOString() },
    data: { type: "test" },
    apns: { headers: { "apns-push-type": "alert", "apns-priority": "10" }, payload: { aps: { sound: "default" } } },
  }, dryRun);
  return { success: res.successCount, failure: res.failureCount,
           errors: res.responses.filter((r) => !r.success).map((r) => r.error?.code ?? "unknown") };
});
```

- **Checklist when nothing arrives:** APNs key uploaded → bundle id matches → device is physical → app has Push capability → `apnsToken` set before the token was uploaded → token in Firestore equals the one printed on device → payload has `apns-push-type` → not a silent push expected to show something.

## Does not exist / common mistakes

- Sending inside a transaction or before the marker commit — send only after `claimEvent` returned true.
- `arrayUnion` digests without a cap — the pending doc can exceed 1 MiB.
- Reading preferences once at cold start and caching — stale after the user toggles.
- Suppressing during quiet hours by delaying the whole trigger with `setTimeout` — functions are billed while waiting and time out; use a task with `scheduleDelaySeconds` or drop.
- `onSchedule` with `timeZone: "Asia/Ho_Chi_Minh"` and per-user local times — pick one timezone for the job and store each user's UTC hour, as above.
- Expecting the emulator to deliver FCM — it does not; only the real service does.

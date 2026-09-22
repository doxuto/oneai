# Sending

All sending goes through `getMessaging()` from `firebase-admin/messaging` (FCM HTTP v1). The legacy HTTP API and the methods built on it are gone.

## The three send methods

| Method | Input | Returns | Use when |
|---|---|---|---|
| `send(message, dryRun?)` | one `Message` (token, topic, or condition) | `Promise<string>` message id `projects/…/messages/…` | Single recipient or topic. Throws on failure. |
| `sendEach(messages[], dryRun?)` | ≤ 500 heterogeneous `Message`s | `BatchResponse { successCount, failureCount, responses: SendResponse[] }` | Different payload per recipient (personalised body, per-locale strings). Never throws for individual failures. |
| `sendEachForMulticast(multicast, dryRun?)` | one `MulticastMessage` with `tokens: string[]` (≤ 500) | `BatchResponse` | Same payload to many tokens. The common case. |

`SendResponse` is `{ success: boolean, messageId?: string, error?: FirebaseError }` and `responses[i]` corresponds to `tokens[i]` / `messages[i]` — the index is how you map failures back to device documents.

`sendEach` / `sendEachForMulticast` issue one HTTP request per message under the hood (there is no batch endpoint any more), in parallel. 500 is the SDK's hard input limit, not a network batch.

`sendMulticast` and `sendAll` were deprecated in firebase-admin 12 and **removed in 13**. `sendToDevice`, `sendToTopic`, `sendToCondition` were removed with the legacy API. If a review finds them, the code does not compile against the target.

## Chunking

```ts
import { getMessaging, type MulticastMessage, type BatchResponse } from "firebase-admin/messaging";

export async function sendToTokens(
  base: Omit<MulticastMessage, "tokens">,
  tokens: string[],
  opts: { dryRun?: boolean } = {}
): Promise<{ sent: number; failed: number; dead: string[]; retryable: string[] }> {
  const out = { sent: 0, failed: 0, dead: [] as string[], retryable: [] as string[] };
  for (let i = 0; i < tokens.length; i += 500) {
    const chunk = tokens.slice(i, i + 500);
    const res: BatchResponse = await getMessaging().sendEachForMulticast({ ...base, tokens: chunk }, opts.dryRun);
    out.sent += res.successCount;
    out.failed += res.failureCount;
    res.responses.forEach((r, idx) => {
      if (r.success) return;
      const code = r.error?.code ?? "unknown";
      if (DEAD_TOKEN_CODES.has(code)) out.dead.push(chunk[idx]);
      else if (RETRYABLE_CODES.has(code)) out.retryable.push(chunk[idx]);
      else logger.error("push permanent failure", { code, message: r.error?.message });
    });
  }
  return out;
}
```

Run chunks sequentially (as above) unless you have measured a need; fan-out to thousands of users belongs in a task queue (`onTaskDispatched`) with `rateLimits`, not in one function invocation.

## Topics and conditions

Topics are server-managed groups. Membership is per token, not per user, so subscribe every device document of a user.

```ts
// ≤ 1000 tokens per call
const res = await getMessaging().subscribeToTopic(tokens, "pro-users");
res.errors.forEach((e) => logger.warn("subscribe failed", { index: e.index, code: e.error.code }));
await getMessaging().unsubscribeFromTopic(tokens, "pro-users");

await getMessaging().send({ topic: "pro-users", notification: { title: "New feature", body: "…" }, apns });
await getMessaging().send({
  condition: "'pro-users' in topics && ('vi' in topics || 'en' in topics)",   // ≤ 5 topics per condition
  notification: { title: "…", body: "…" },
});
```

- Topic names match `[a-zA-Z0-9-_.~%]+`. No `/topics/` prefix in the v1 API.
- Topic sends are best-effort broadcast: no per-device result, no dead-token feedback. Use them for "everyone on plan X", not for anything a user must receive.
- The client can also subscribe with `Messaging.messaging().subscribe(toTopic:)`, but server-side subscription keeps the mapping auditable and lets the prune job unsubscribe dead tokens. Pick one owner.
- Subscriptions persist across app restarts but not across token rotation — resubscribe from the same place you upload the token (a Firestore trigger on `users/{uid}/devices/{id}` create/update is a good hook).

## Dry run

`send(msg, true)` / `sendEachForMulticast(msg, true)` validate the message against FCM and APNs (including the token's validity and payload size) without delivering. Use it:

- in an emulator-side smoke test against a real token (the emulator does not emulate FCM; the call goes to the real service),
- in a `validatePush` callable behind an admin claim, to check a payload before a campaign,
- never as the default in production code paths — a forgotten `true` is a silent outage.

## Error handling table

`r.error.code` (and `err.code` from a thrown `send`) is a string from the `messaging/*` namespace.

| Code | Meaning | Action |
|---|---|---|
| `messaging/registration-token-not-registered` | Token expired, app uninstalled, or token rotated | Delete the device document. |
| `messaging/invalid-registration-token` | Malformed token | Delete the device document; log — it is a client bug. |
| `messaging/invalid-argument` | Bad message shape or bad token | Fix the code. If tied to a token, delete the document. |
| `messaging/invalid-payload`, `messaging/invalid-data-payload-key`, `messaging/payload-size-limit-exceeded` | Message content invalid or > 4 KB | Bug. Do not retry. |
| `messaging/invalid-apns-credentials`, `messaging/third-party-auth-error` | APNs key missing/wrong in Firebase console | Configuration. Alert an engineer; do not retry. |
| `messaging/mismatched-credential`, `messaging/authentication-error` | Wrong project / service account | Configuration. |
| `messaging/message-rate-exceeded`, `messaging/device-message-rate-exceeded`, `messaging/topics-message-rate-exceeded` | Quota | Back off (seconds to minutes), then retry. |
| `messaging/server-unavailable` (503), `messaging/internal-error` (500), `messaging/unknown-error` | Transient | Retry with exponential backoff. |
| `messaging/too-many-topics` | Token subscribed to > 2000 topics | Design problem. |

Map the outcome, do not swallow: a permanent failure that is not a dead token is a bug in the sender and should surface in Error Reporting via `logger.error`.

## Retry with backoff

The admin SDK already retries a small number of times internally on 503 and connection resets. Add your own layer only for the codes above, with jitter and a cap, and only for the tokens that failed transiently.

```ts
const RETRYABLE_CODES = new Set([
  "messaging/server-unavailable",
  "messaging/internal-error",
  "messaging/unknown-error",
  "messaging/message-rate-exceeded",
  "messaging/device-message-rate-exceeded",
]);

async function withBackoff<T>(fn: () => Promise<T>, attempts = 4, baseMs = 500): Promise<T> {
  let lastErr: unknown;
  for (let i = 0; i < attempts; i++) {
    try {
      return await fn();
    } catch (e: unknown) {
      lastErr = e;
      const code = (e as { code?: string }).code ?? "";
      if (!RETRYABLE_CODES.has(code)) throw e;
      const delay = baseMs * 2 ** i + Math.random() * baseMs;   // jittered exponential
      await new Promise((r) => setTimeout(r, delay));
    }
  }
  throw lastErr;
}

// single send
await withBackoff(() => getMessaging().send(message));

// multicast: retry only the transient subset, once, after the first pass
const first = await sendToTokens(base, tokens);
if (first.retryable.length) {
  await new Promise((r) => setTimeout(r, 2000));
  await sendToTokens(base, first.retryable);
}
```

Budget the retries against `timeoutSeconds`. A Firestore-trigger function has 60 s by default; four attempts with base 500 ms fit; a minute of backoff does not. For large fan-outs, move to `onTaskDispatched` with `retryConfig: { maxAttempts: 5, minBackoffSeconds: 10 }` and let Cloud Tasks own the retry — then the handler simply throws on transient failure.

## Logging

One structured line per send call, never one per token on success.

```ts
logger.info("push", {
  kind: "note.shared",
  uid,
  tokens: tokens.length,
  success: res.successCount,
  failure: res.failureCount,
  dead: dead.length,
  dryRun: false,
});
```

Set `fcmOptions.analyticsLabel` (≤ 50 chars, `[a-zA-Z0-9-_.~%]`) on every message so the Firebase console's FCM reports break down by campaign type. Log the message id from `send()` only at debug level.

Never log the token itself at info level — treat it like a credential. Log the device document path instead.

## Localisation: server-side vs `loc-key`

| | Server-side strings | `loc-key` / `loc-args` |
|---|---|---|
| Where strings live | Functions code (or a Firestore `i18n` doc) | App bundle `Localizable.strings` |
| Change wording without app release | yes | no |
| Works for users on an old app version | yes | only if the key exists in that version — otherwise iOS shows the raw key |
| Needs per-device locale in the registry | yes (`locale` field) | no (device decides) |
| Grouped send (`sendEachForMulticast`) | one call per locale group | one call for everyone |

Recommendation for this bundle: server-side. Read `locale` from each device document, group tokens by language, and call `sendEachForMulticast` once per group. Fall back to English when the locale is missing.

```ts
const strings = {
  vi: { title: (n: string) => `${n} đã chia sẻ ghi chú`, body: (t: string) => t },
  en: { title: (n: string) => `${n} shared a note`, body: (t: string) => t },
} as const;

const groups = new Map<keyof typeof strings, string[]>();
for (const d of devices.docs) {
  const lang = ((d.get("locale") as string | undefined) ?? "en").startsWith("vi") ? "vi" : "en";
  groups.set(lang, [...(groups.get(lang) ?? []), d.get("token") as string]);
}
for (const [lang, tokens] of groups) {
  const s = strings[lang];
  await sendToTokens({ ...base, notification: { title: s.title(fromName), body: s.body(noteTitle) } }, tokens);
}
```

Use `loc-key` only when the app must render strings itself (e.g. plural rules handled by `Localizable.stringsdict`).

## Does not exist / common mistakes

- `sendMulticast`, `sendAll`, `sendToDevice`, `sendToTopic`, `sendToCondition` — removed.
- `getMessaging().send({ tokens: [...] })` — `Message` takes a single `token`; multiple tokens need `sendEachForMulticast`.
- `sendEachForMulticast` with > 500 tokens — throws `messaging/invalid-argument` before sending anything.
- Treating `send()` resolving as "delivered" — it means FCM accepted the message. APNs delivery is not reported back per message.
- Catching `sendEachForMulticast` in try/catch and assuming failures throw — they do not; inspect `responses`.
- `condition: "topicA && topicB"` — conditions need the `'x' in topics` form.
- Retrying `messaging/registration-token-not-registered` — it never recovers; delete.
- Passing `dryRun` as part of the message object — it is the second positional argument.

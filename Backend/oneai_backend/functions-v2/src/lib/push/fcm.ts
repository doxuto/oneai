import { getMessaging, type Message } from "firebase-admin/messaging";
import { log } from "../logging.js";
import type { PushMessage, PushSendResult, Pusher } from "./types.js";

/** FCM error codes that mean the token will never work again. */
const DEAD_TOKEN_CODES: ReadonlySet<string> = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
  "messaging/invalid-argument",
]);

export function toFcmMessage(m: PushMessage): Message {
  return {
    token: m.token,
    notification: { title: m.title, body: m.body },
    data: m.data,
    android: {
      priority: "high",
      collapseKey: m.collapseKey,
      notification: { channelId: "transcription", sound: "default", tag: m.collapseKey },
    },
    apns: {
      headers: m.collapseKey ? { "apns-collapse-id": m.collapseKey } : {},
      payload: { aps: { sound: "default", "thread-id": m.data.minuteId ?? "oneai" } },
    },
  };
}

/** Classifies one FCM outcome. Exported so the mapping is unit-tested without FCM. */
export function classify(token: string, r: { success: boolean; error?: { code?: string; message?: string } | null }): PushSendResult {
  if (r.success) return { token, ok: true, unregistered: false };
  const code = r.error?.code ?? "unknown";
  return { token, ok: false, unregistered: DEAD_TOKEN_CODES.has(code), error: code };
}

export function fcmPusher(): Pusher {
  return {
    async send(messages) {
      if (messages.length === 0) return [];
      const res = await getMessaging().sendEach(messages.map(toFcmMessage));
      const out = res.responses.map((r, i) => classify(messages[i]!.token, { success: r.success, error: r.error ? { code: r.error.code, message: r.error.message } : null }));
      log.info("push.sent", { count: messages.length, ok: res.successCount, failed: res.failureCount });
      return out;
    },
  };
}

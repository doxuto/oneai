import { FieldValue } from "firebase-admin/firestore";
import type { Deps } from "../lib/deps.js";
import { rethrow } from "../lib/errors.js";
import { requireCaller, type Caller } from "../lib/handler.js";
import { logDone } from "../lib/logging.js";
import { parse } from "../lib/validate.js";
import { deviceIdOf, devicesCol, toPrefs } from "./_shared.js";
import {
  RegisterDeviceInput, UnregisterDeviceInput, UpdateNotificationPrefsInput,
  type RegisterDeviceOutput, type UnregisterDeviceOutput, type UpdateNotificationPrefsOutput,
} from "./types.js";

/**
 * Upserts the device under the caller. A token identifies a device, not a
 * person: when another account signs in on the same phone, the token is
 * moved — the previous owner must not keep receiving that phone's pushes.
 */
export async function registerDeviceHandler(caller: Caller | undefined, raw: unknown, deps: Deps): Promise<RegisterDeviceOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(RegisterDeviceInput, raw, deps.minClientVersion);
  const id = deviceIdOf(input.token);
  try {
    const ref = devicesCol(deps.db, uid).doc(id);
    const [elsewhere, existing] = await Promise.all([
      deps.db.collectionGroup("devices").where("token", "==", input.token).get(),
      ref.get(),
    ]);
    const batch = deps.db.batch();
    let moved = 0;
    for (const d of elsewhere.docs) {
      if (d.ref.parent.parent?.id !== uid) { batch.delete(d.ref); moved++; }
    }
    batch.set(ref, {
      token: input.token,
      platform: input.client.platform,
      locale: input.locale ?? null,
      appVersion: input.client.appVersion,
      createdAt: existing.exists ? existing.get("createdAt") ?? FieldValue.serverTimestamp() : FieldValue.serverTimestamp(),
      lastSeenAt: FieldValue.serverTimestamp(),
    });
    await batch.commit();
    logDone("device.registered", startedAt, { uid, platform: input.client.platform, moved });
    return {};
  } catch (err) {
    return rethrow(err, "device.register.failed", { uid });
  }
}

/** Idempotent; unknown token is fine (already gone). */
export async function unregisterDeviceHandler(caller: Caller | undefined, raw: unknown, deps: Deps): Promise<UnregisterDeviceOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(UnregisterDeviceInput, raw, deps.minClientVersion);
  try {
    await devicesCol(deps.db, uid).doc(deviceIdOf(input.token)).delete();
    logDone("device.unregistered", startedAt, { uid });
    return {};
  } catch (err) {
    return rethrow(err, "device.unregister.failed", { uid });
  }
}

export async function updateNotificationPrefsHandler(caller: Caller | undefined, raw: unknown, deps: Deps): Promise<UpdateNotificationPrefsOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(UpdateNotificationPrefsInput, raw, deps.minClientVersion);
  try {
    const ref = deps.db.doc(`users/${uid}`);
    const notifications = { transcriptionDone: input.transcriptionDone };
    await ref.set({ notifications, updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    logDone("notifications.updated", startedAt, { uid, transcriptionDone: input.transcriptionDone });
    return { notifications: toPrefs(notifications) };
  } catch (err) {
    return rethrow(err, "notifications.update.failed", { uid });
  }
}

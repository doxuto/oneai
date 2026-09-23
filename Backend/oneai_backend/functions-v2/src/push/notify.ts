/**
 * "Your note is ready" — sent by the pipeline (and the stale-job reaper)
 * when a job reaches a terminal state. Never throws: a push problem must not
 * turn a finished note into a failed job.
 */
import type { Deps } from "../lib/deps.js";
import { log } from "../lib/logging.js";
import type { PushMessage } from "../lib/push/types.js";
import { notificationCopy, type PushKind } from "./copy.js";
import { devicesCol, toPrefs } from "./_shared.js";
import type { DeviceDoc } from "./types.js";

export interface MinuteEvent {
  minuteId: string;
  title: string;
  kind: PushKind;
}

export interface NotifyReport {
  sent: number;
  pruned: number;
  skipped: "prefs" | "noDevices" | null;
}

export async function notifyMinuteResult(deps: Deps, uid: string, ev: MinuteEvent): Promise<NotifyReport> {
  try {
    const [userSnap, devices] = await Promise.all([deps.db.doc(`users/${uid}`).get(), devicesCol(deps.db, uid).get()]);
    const prefs = toPrefs((userSnap.data() as { notifications?: unknown } | undefined)?.notifications);
    if (!prefs.transcriptionDone) return { sent: 0, pruned: 0, skipped: "prefs" };
    if (devices.empty) return { sent: 0, pruned: 0, skipped: "noDevices" };

    const messages: PushMessage[] = devices.docs.map((d) => {
      const dev = d.data() as DeviceDoc;
      const copy = notificationCopy(ev.kind, dev.locale, ev.title);
      return {
        token: dev.token,
        title: copy.title,
        body: copy.body,
        data: { type: ev.kind, minuteId: ev.minuteId },
        collapseKey: `minute:${ev.minuteId}`,
      };
    });

    const results = await deps.services.push.send(messages);
    const dead = results.filter((r) => r.unregistered).map((r) => r.token);
    if (dead.length > 0) {
      const batch = deps.db.batch();
      for (const d of devices.docs) if (dead.includes((d.data() as DeviceDoc).token)) batch.delete(d.ref);
      await batch.commit();
    }
    const sent = results.filter((r) => r.ok).length;
    log.info("push.minute", { uid, minuteId: ev.minuteId, kind: ev.kind, sent, pruned: dead.length, failed: results.length - sent });
    return { sent, pruned: dead.length, skipped: null };
  } catch (err) {
    log.error("push.minute.failed", { uid, minuteId: ev.minuteId, kind: ev.kind, error: String(err) });
    return { sent: 0, pruned: 0, skipped: null };
  }
}

/**
 * S11-03b — hourly: every review doc whose `remindAt` has passed gets one push
 * per user ("12 cards are due"), then `remindAt` is cleared so nobody is
 * nagged; the app re-arms it on its next sync. Never throws per user: one bad
 * token must not stop the others.
 */
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import type { Deps } from "../lib/deps.js";
import { liveDeps } from "../lib/deps.js";
import { log } from "../lib/logging.js";
import type { PushMessage } from "../lib/push/types.js";
import { devicesCol, toPrefs } from "../push/_shared.js";
import { reviewDueCopy } from "../push/copy.js";
import type { DeviceDoc } from "../push/types.js";
import { groupByUser, type DueNote } from "../study/schedule.js";
import type { ReviewDoc } from "../study/types.js";

export const REMIND_MAX_PER_RUN = 1000;

export interface RemindReport { notes: number; users: number; sent: number; skipped: number }

export async function remindDueReviews(deps: Deps, max = REMIND_MAX_PER_RUN): Promise<RemindReport> {
  const t0 = Date.now();
  const now = Timestamp.fromDate(deps.now());
  const snap = await deps.db.collectionGroup("study").where("remindAt", "<=", now).limit(max).get();
  const due: DueNote[] = [];
  const refs = new Map<string, FirebaseFirestore.DocumentReference>();
  for (const d of snap.docs) {
    const r = d.data() as ReviewDoc;
    if (!r.uid || !r.minuteId) continue;
    due.push({ uid: r.uid, minuteId: r.minuteId, title: r.title ?? "", dueCount: r.dueCount ?? 0 });
    refs.set(`${r.uid}/${r.minuteId}`, d.ref);
  }
  let sent = 0, skipped = 0;
  const groups = groupByUser(due);
  for (const g of groups) {
    try {
      const [userSnap, devices] = await Promise.all([deps.db.doc(`users/${g.uid}`).get(), devicesCol(deps.db, g.uid).get()]);
      const prefs = toPrefs((userSnap.data() as { notifications?: unknown } | undefined)?.notifications);
      if (prefs.reviewReminders && !devices.empty && g.dueCount > 0) {
        const single = g.notes.length === 1 ? g.notes[0]! : null;
        const messages: PushMessage[] = devices.docs.map((d) => {
          const dev = d.data() as DeviceDoc;
          const copy = reviewDueCopy(dev.locale, g.dueCount, g.notes.length, single?.title ?? "");
          return {
            token: dev.token,
            title: copy.title,
            body: copy.body,
            data: { type: "reviewDue", ...(single ? { minuteId: single.minuteId } : {}) },
            collapseKey: `review:${g.uid}`,
          };
        });
        const results = await deps.services.push.send(messages);
        const dead = results.filter((r) => r.unregistered).map((r) => r.token);
        if (dead.length > 0) {
          const batch = deps.db.batch();
          for (const d of devices.docs) if (dead.includes((d.data() as DeviceDoc).token)) batch.delete(d.ref);
          await batch.commit();
        }
        sent += results.filter((r) => r.ok).length;
      } else {
        skipped++;
      }
    } catch (err) {
      log.error("study.remind.user_failed", { uid: g.uid, error: String(err) });
    }
    // Cleared whether or not a push went out: a disabled pref or a phone with
    // no token should not keep the doc in every hourly scan.
    const batch = deps.db.batch();
    for (const n of g.notes) batch.update(refs.get(`${n.uid}/${n.minuteId}`)!, { remindAt: null, remindedAt: FieldValue.serverTimestamp() });
    await batch.commit();
  }
  log.info("study.remind", { notes: due.length, users: groups.length, sent, skipped, ms: Date.now() - t0 });
  return { notes: due.length, users: groups.length, sent, skipped };
}

export const remindReviews = onSchedule(
  { schedule: "5 * * * *", timeZone: "Etc/UTC", memory: "256MiB", timeoutSeconds: 300, retryCount: 0 },
  async () => { await remindDueReviews(liveDeps()); },
);

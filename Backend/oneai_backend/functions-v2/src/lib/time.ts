import { Timestamp } from "firebase-admin/firestore";

/** The project's quota period boundary. */
export const APP_TIMEZONE = "Asia/Ho_Chi_Minh";

/** Firestore Timestamp never crosses the wire — ISO-8601 only. */
export function toIso(value: Timestamp | Date | null | undefined): string | null {
  if (value === null || value === undefined) return null;
  const d = value instanceof Timestamp ? value.toDate() : value;
  return d.toISOString();
}

/** "2026-09-22" in APP_TIMEZONE — the quota period document id. */
export function periodIdFor(now: Date, timeZone: string = APP_TIMEZONE): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
}

/** Start of the next period, for `resetAt` in a resource-exhausted error. */
export function nextPeriodStart(now: Date, timeZone: string = APP_TIMEZONE): Date {
  const next = new Date(now.getTime() + 24 * 60 * 60 * 1000);
  const todayKey = periodIdFor(now, timeZone);
  let probe = new Date(now.getTime());
  for (let i = 0; i < 48; i++) {
    probe = new Date(probe.getTime() + 60 * 60 * 1000);
    if (periodIdFor(probe, timeZone) !== todayKey) {
      probe.setUTCMinutes(0, 0, 0);
      return probe;
    }
  }
  return next;
}

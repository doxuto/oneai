import { createHash } from "node:crypto";
import type { CollectionReference, Firestore } from "firebase-admin/firestore";
import type { NotificationPrefs } from "./types.js";

/** Tokens can be 4 KB; the doc id is a stable hash of it. */
export const deviceIdOf = (token: string): string => createHash("sha256").update(token).digest("hex").slice(0, 40);

export const devicesCol = (db: Firestore, uid: string): CollectionReference => db.collection(`users/${uid}/devices`);

export const DEFAULT_PREFS: NotificationPrefs = { transcriptionDone: true };

export function toPrefs(raw: unknown): NotificationPrefs {
  const d = (raw && typeof raw === "object" ? raw : {}) as Record<string, unknown>;
  return { transcriptionDone: typeof d.transcriptionDone === "boolean" ? d.transcriptionDone : DEFAULT_PREFS.transcriptionDone };
}

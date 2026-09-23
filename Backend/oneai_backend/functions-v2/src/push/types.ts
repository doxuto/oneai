import { z } from "zod";
import { withClient } from "../types/common.js";

/** FCM tokens are opaque; bound the size, nothing else. */
const Token = z.string().min(20).max(4096);

export const RegisterDeviceInput = withClient({
  token: Token,
  /** BCP-47 as the OS reports it; used to pick notification language. */
  locale: z.string().max(35).optional(),
}).strict();
export type RegisterDeviceInput = z.infer<typeof RegisterDeviceInput>;

export const UnregisterDeviceInput = withClient({ token: Token }).strict();

export const UpdateNotificationPrefsInput = withClient({
  transcriptionDone: z.boolean().optional(),
  /** S11-03b: "N cards are due" at 19:00 local. */
  reviewReminders: z.boolean().optional(),
}).strict().refine((v) => v.transcriptionDone !== undefined || v.reviewReminders !== undefined, { message: "nothing to update" });
export type UpdateNotificationPrefsInput = z.infer<typeof UpdateNotificationPrefsInput>;

export interface NotificationPrefs {
  /** Push when a note finishes (or fails). Default true. */
  transcriptionDone: boolean;
  /** Push when flashcards are due for review (S11-03b). Default true. */
  reviewReminders: boolean;
}

export type RegisterDeviceOutput = Record<string, never>;
export type UnregisterDeviceOutput = Record<string, never>;
export interface UpdateNotificationPrefsOutput { notifications: NotificationPrefs }

/** users/{uid}/devices/{deviceId} — server-only. */
export interface DeviceDoc {
  token: string;
  platform: string;
  locale: string | null;
  appVersion: string;
  createdAt: FirebaseFirestore.Timestamp;
  lastSeenAt: FirebaseFirestore.Timestamp;
}

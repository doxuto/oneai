import type { DocumentData } from "firebase-admin/firestore";
import { toIso } from "../lib/time.js";
import type { Plan, UserOutput } from "./types.js";

/** What `users/{uid}` looks like on disk. Everything optional — old docs exist. */
export interface UserDoc {
  email?: string | null;
  displayName?: string | null;
  photoUrl?: string | null;
  plan?: string;
  planExpiresAt?: FirebaseFirestore.Timestamp | null;
  minuteCount?: number;
  createdAt?: FirebaseFirestore.Timestamp;
  updatedAt?: FirebaseFirestore.Timestamp;
  lastSeenAt?: FirebaseFirestore.Timestamp;
}

/**
 * Effective plan. `plan` alone is not trusted: a missed RevenueCat EXPIRATION
 * webhook must not grant premium forever (docs/06 §1, OQ-04).
 */
export function effectivePlan(doc: UserDoc, now: Date): Plan {
  if (doc.plan !== "premium") return "free";
  const exp = doc.planExpiresAt;
  if (exp && exp.toDate().getTime() < now.getTime()) return "free";
  return "premium";
}

/** Explicit output mapper — never `return snap.data()`. */
export function toUserOutput(uid: string, raw: DocumentData | undefined, now: Date): UserOutput {
  const d = (raw ?? {}) as UserDoc;
  return {
    id: uid,
    email: typeof d.email === "string" ? d.email : null,
    displayName: typeof d.displayName === "string" ? d.displayName : null,
    photoUrl: typeof d.photoUrl === "string" ? d.photoUrl : null,
    plan: effectivePlan(d, now),
    planExpiresAt: toIso(d.planExpiresAt ?? null),
    minuteCount: typeof d.minuteCount === "number" ? d.minuteCount : 0,
    createdAt: toIso(d.createdAt ?? null),
  };
}

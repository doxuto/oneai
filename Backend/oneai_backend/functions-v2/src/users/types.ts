import { z } from "zod";
import { withClient } from "../types/common.js";

export const GetMeInput = withClient({});
export type GetMeInput = z.infer<typeof GetMeInput>;

export type Plan = "free" | "premium";

export interface QuotaOutput {
  /** Seconds of audio charged today. */
  usedSeconds: number;
  /** 0 = unlimited (premium). */
  limitSeconds: number;
  /** Longest single recording the plan accepts. */
  maxDurationSeconds: number;
  resetAt: string;
}

export interface UserOutput {
  id: string;
  email: string | null;
  displayName: string | null;
  photoUrl: string | null;
  plan: Plan;
  planExpiresAt: string | null;
  minuteCount: number;
  createdAt: string | null;
  notifications: { transcriptionDone: boolean };
}

export interface GetMeOutput {
  user: UserOutput;
  quota: QuotaOutput;
}

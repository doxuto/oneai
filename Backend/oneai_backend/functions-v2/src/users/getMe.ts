import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { db } from "../lib/admin.js";
import { parse } from "../lib/validate.js";
import { rethrow } from "../lib/errors.js";
import { log, logDone } from "../lib/logging.js";
import { periodIdFor, nextPeriodStart, toIso } from "../lib/time.js";
import { withClient } from "../types/common.js";
import { FREE_DAILY_LIMIT, PREMIUM_DAILY_LIMIT } from "../lib/params.js";

const GetMeInput = withClient({});

export interface QuotaOutput {
  used: number;
  limit: number;
  rewardBonus: number;
  resetAt: string;
}

export interface GetMeOutput {
  user: {
    id: string;
    email: string | null;
    displayName: string | null;
    photoUrl: string | null;
    plan: "free" | "premium";
    planExpiresAt: string | null;
    minuteCount: number;
    createdAt: string | null;
  };
  quota: QuotaOutput;
}

export const getMe = onCall(
  { enforceAppCheck: true, memory: "256MiB", timeoutSeconds: 30 },
  async (request: CallableRequest<unknown>): Promise<GetMeOutput> => {
    const startedAt = Date.now();
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required");
    parse(GetMeInput, request.data);

    const uid = request.auth.uid;
    try {
      const now = new Date();
      const periodId = periodIdFor(now);
      const [userSnap, quotaSnap] = await Promise.all([
        db.doc(`users/${uid}`).get(),
        db.doc(`users/${uid}/quota/${periodId}`).get(),
      ]);

      if (!userSnap.exists) {
        // onUserCreated has not landed yet; do not invent a profile.
        log.warn("user.profile_missing", { uid });
        throw new HttpsError("not-found", "Profile is still being created");
      }

      const u = userSnap.data() ?? {};
      const plan = u.plan === "premium" ? "premium" : "free";
      const q = quotaSnap.data() ?? {};
      const baseLimit =
        typeof q.baseLimit === "number"
          ? q.baseLimit
          : plan === "premium"
            ? PREMIUM_DAILY_LIMIT.value()
            : FREE_DAILY_LIMIT.value();
      const rewardBonus = typeof q.rewardBonus === "number" ? q.rewardBonus : 0;

      const out: GetMeOutput = {
        user: {
          id: uid,
          email: typeof u.email === "string" ? u.email : null,
          displayName: typeof u.displayName === "string" ? u.displayName : null,
          photoUrl: typeof u.photoUrl === "string" ? u.photoUrl : null,
          plan,
          planExpiresAt: toIso(u.planExpiresAt ?? null),
          minuteCount: typeof u.minuteCount === "number" ? u.minuteCount : 0,
          createdAt: toIso(u.createdAt ?? null),
        },
        quota: {
          used: typeof q.used === "number" ? q.used : 0,
          limit: baseLimit + rewardBonus,
          rewardBonus,
          resetAt: nextPeriodStart(now).toISOString(),
        },
      };
      logDone("user.me", startedAt, { uid, plan });
      return out;
    } catch (err) {
      return rethrow(err, "user.me.failed", { uid });
    }
  },
);

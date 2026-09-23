import { HttpsError } from "firebase-functions/v2/https";
import type { Deps } from "../lib/deps.js";
import { requireCaller, type Caller } from "../lib/handler.js";
import { log } from "../lib/logging.js";
import { nextPeriodStart, periodIdFor } from "../lib/time.js";
import { parse } from "../lib/validate.js";
import { rethrow } from "../lib/errors.js";
import { toUserOutput } from "./_shared.js";
import { GetMeInput, type GetMeOutput } from "./types.js";

/** Shape of `users/{uid}/quota/{periodId}`. */
interface QuotaDoc {
  usedSeconds?: number;
  limitSeconds?: number;
}

export async function getMeHandler(
  caller: Caller | undefined,
  raw: unknown,
  deps: Deps,
): Promise<GetMeOutput> {
  const { uid } = requireCaller(caller);
  parse(GetMeInput, raw, deps.minClientVersion);

  try {
    const now = deps.now();
    const periodId = periodIdFor(now);
    const [userSnap, quotaSnap] = await Promise.all([
      deps.db.doc(`users/${uid}`).get(),
      deps.db.doc(`users/${uid}/quota/${periodId}`).get(),
    ]);

    if (!userSnap.exists) {
      // onUserCreated has not landed yet. Do not invent a profile.
      log.warn("user.profile_missing", { uid });
      throw new HttpsError("not-found", "Profile is still being created");
    }

    const user = toUserOutput(uid, userSnap.data(), now);
    const q = (quotaSnap.data() ?? {}) as QuotaDoc;
    const limits = deps.limits[user.plan];

    return {
      user,
      quota: {
        usedSeconds: typeof q.usedSeconds === "number" ? q.usedSeconds : 0,
        // The plan's ceiling wins over a stale doc written under another plan.
        limitSeconds: user.plan === "premium" ? limits.dailySeconds : (typeof q.limitSeconds === "number" ? q.limitSeconds : limits.dailySeconds),
        maxDurationSeconds: limits.maxDurationSeconds,
        resetAt: nextPeriodStart(now).toISOString(),
      },
    };
  } catch (err) {
    return rethrow(err, "user.me.failed", { uid });
  }
}

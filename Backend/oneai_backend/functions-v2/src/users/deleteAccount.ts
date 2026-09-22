import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { z } from "zod";
import { getAdminAuth } from "../lib/admin.js";
import { liveDeps } from "../lib/deps.js";
import { rethrow } from "../lib/errors.js";
import { callerOf, requireCaller, type Caller } from "../lib/handler.js";
import { log, logDone } from "../lib/logging.js";
import { parse } from "../lib/validate.js";
import { withClient } from "../types/common.js";
import type { Deps } from "../lib/deps.js";

export const DeleteAccountInput = withClient({ confirm: z.literal(true) }).strict();

/**
 * Deletes the Firebase Auth user server-side; onUserDeleted then removes
 * Firestore and Storage. Doing it here avoids the client-side
 * "requires-recent-login" wall, and the data-deletion path is the same
 * trigger either way, so there is exactly one implementation of "erase me".
 */
export async function deleteAccountHandler(
  caller: Caller | undefined,
  raw: unknown,
  deps: Deps,
  deleteAuthUser: (uid: string) => Promise<void>,
): Promise<Record<string, never>> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  parse(DeleteAccountInput, raw, deps.minClientVersion);
  try {
    // Mark first so a client reading the profile mid-deletion sees it.
    await deps.db.doc(`users/${uid}`).set({ deletionRequestedAt: deps.now() }, { merge: true });
    await deleteAuthUser(uid);
    logDone("user.delete.requested", startedAt, { uid });
    return {};
  } catch (err) {
    if ((err as { code?: string }).code === "auth/user-not-found") {
      log.warn("user.delete.already_gone", { uid });
      throw new HttpsError("not-found", "Account not found");
    }
    return rethrow(err, "user.delete.failed", { uid });
  }
}

export const deleteAccount = onCall(
  { enforceAppCheck: true, memory: "256MiB", timeoutSeconds: 30 },
  (request: CallableRequest<unknown>) =>
    deleteAccountHandler(callerOf(request), request.data, liveDeps(), (uid) => getAdminAuth().deleteUser(uid)),
);

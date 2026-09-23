/**
 * The handler/wrapper split (firebase-testing-pro):
 *   - a handler is a plain async function `(caller, raw, deps) => output`
 *   - the `onCall` export is glue and nothing else
 * Tests import the handler. Nothing in here touches firebase-admin.
 */
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";

export interface Caller {
  uid: string;
  /** `request.auth.token.firebase.sign_in_provider` — "anonymous", "google.com", … */
  signInProvider: string | undefined;
}

export function callerOf(request: CallableRequest<unknown>): Caller | undefined {
  const auth = request.auth;
  if (!auth) return undefined;
  const token = auth.token as { firebase?: { sign_in_provider?: string } } | undefined;
  return { uid: auth.uid, signInProvider: token?.firebase?.sign_in_provider };
}

/** First line of every handler. */
export function requireCaller(caller: Caller | undefined): Caller {
  if (!caller) throw new HttpsError("unauthenticated", "Sign in required");
  if (caller.signInProvider === "anonymous") {
    throw new HttpsError("permission-denied", "Link an account to continue", {
      reason: "anonymous",
    });
  }
  return caller;
}

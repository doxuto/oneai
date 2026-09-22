/**
 * RevenueCat webhook logic, pure over Deps. The wrapper only adapts req/res.
 *
 * v1 compared the bearer with `!==` against an env var that could be
 * undefined — so `Authorization: Bearer undefined` passed — and trusted
 * app_user_id as a uid, then called update() which threw on a missing doc.
 */
import { timingSafeEqual } from "node:crypto";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { z } from "zod";
import type { Deps } from "../lib/deps.js";
import { log } from "../lib/logging.js";

export const ENTITLEMENT_ID = "pro";

const Event = z.object({
  type: z.string(),
  app_user_id: z.string().min(1).max(128),
  original_app_user_id: z.string().optional(),
  entitlement_ids: z.array(z.string()).optional().nullable(),
  expiration_at_ms: z.number().optional().nullable(),
  id: z.string().optional(),
});
export const WebhookBody = z.object({ event: Event, api_version: z.string().optional() });

/** Grants premium. CANCELLATION only turns off auto-renew; access lasts until EXPIRATION. */
const GRANTING: ReadonlySet<string> = new Set(["INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION", "NON_RENEWING_PURCHASE", "PRODUCT_CHANGE", "TEMPORARY_ENTITLEMENT_GRANT"]);
const REVOKING: ReadonlySet<string> = new Set(["EXPIRATION"]);

export type WebhookResult = { status: 200 | 400 | 401 | 404; body: string };

export function authorized(header: string | undefined, secret: string): boolean {
  if (!secret || !header) return false;
  const expected = Buffer.from(`Bearer ${secret}`);
  const got = Buffer.from(header);
  return expected.length === got.length && timingSafeEqual(expected, got);
}

export async function handleRevenueCat(rawBody: unknown, deps: Deps): Promise<WebhookResult> {
  const parsed = WebhookBody.safeParse(rawBody);
  if (!parsed.success) return { status: 400, body: "bad payload" };
  const ev = parsed.data.event;
  const uid = ev.app_user_id;

  // Only act on a real Firebase user; anonymous RevenueCat ids ($RCAnonymousID:…) are ignored.
  if (uid.startsWith("$RC") || uid.includes("/")) {
    log.info("revenuecat.ignored_anonymous", { type: ev.type });
    return { status: 200, body: "ignored" };
  }
  const userRef = deps.db.doc(`users/${uid}`);
  if (!(await userRef.get()).exists) {
    log.warn("revenuecat.unknown_user", { uid, type: ev.type });
    return { status: 404, body: "unknown user" };
  }

  const forOurEntitlement = !ev.entitlement_ids || ev.entitlement_ids.length === 0 || ev.entitlement_ids.includes(ENTITLEMENT_ID);
  if (!forOurEntitlement) {
    log.info("revenuecat.other_entitlement", { uid, type: ev.type });
    return { status: 200, body: "ignored" };
  }

  const expiresAt = typeof ev.expiration_at_ms === "number" ? Timestamp.fromMillis(ev.expiration_at_ms) : null;

  if (GRANTING.has(ev.type)) {
    await userRef.set({ plan: "premium", planExpiresAt: expiresAt, planSource: "revenuecat", planUpdatedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    log.info("revenuecat.granted", { uid, type: ev.type, expiresAt: expiresAt?.toDate().toISOString() ?? null });
    return { status: 200, body: "ok" };
  }
  if (REVOKING.has(ev.type)) {
    await userRef.set({ plan: "free", planExpiresAt: null, planSource: "revenuecat", planUpdatedAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
    log.info("revenuecat.revoked", { uid, type: ev.type });
    return { status: 200, body: "ok" };
  }
  // CANCELLATION, BILLING_ISSUE, SUBSCRIBER_ALIAS, TRANSFER, TEST, … — record the expiry if given, change nothing else.
  if (expiresAt) await userRef.set({ planExpiresAt: expiresAt, planUpdatedAt: FieldValue.serverTimestamp() }, { merge: true });
  log.info("revenuecat.noop", { uid, type: ev.type });
  return { status: 200, body: "ok" };
}

import { randomBytes } from "node:crypto";
import { FieldValue, Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";
import type { Deps } from "../lib/deps.js";
import { rethrow } from "../lib/errors.js";
import { requireCaller, type Caller } from "../lib/handler.js";
import { logDone } from "../lib/logging.js";
import { toIso } from "../lib/time.js";
import { parse } from "../lib/validate.js";
import { loadOwnedMinute } from "../minutes/_shared.js";
import { CreateShareLinkInput, RevokeShareLinkInput, type CreateShareLinkOutput, type RevokeShareLinkOutput, type ShareDoc, type ShareInfo } from "./types.js";

/** 24 random bytes → 32 url-safe chars; unguessable, no user data inside. */
export function newShareToken(): string {
  return randomBytes(24).toString("base64url");
}

export function shareUrl(base: string, token: string): string {
  return `${base}${base.includes("?") ? "&" : "?"}t=${token}`;
}

export function toShareInfo(base: string, token: string, d: ShareDoc): ShareInfo {
  return {
    url: shareUrl(base, token),
    includeTranscript: d.includeTranscript === true,
    createdAt: toIso(d.createdAt ?? null) ?? "1970-01-01T00:00:00.000Z",
    views: typeof d.views === "number" ? d.views : 0,
  };
}

/**
 * One live link per note. Calling again returns the existing link (idempotent)
 * unless `includeTranscript` changed, in which case the old token is revoked
 * and a new one issued — a link never silently starts exposing more.
 */
export async function createShareLinkHandler(caller: Caller | undefined, raw: unknown, deps: Deps): Promise<CreateShareLinkOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(CreateShareLinkInput, raw, deps.minClientVersion);
  try {
    const { ref, doc } = await loadOwnedMinute(deps.db, uid, input.minuteId);
    if (doc.status !== "ready") throw new HttpsError("failed-precondition", "This note is not ready yet", { reason: "notReady" });

    const existingToken = typeof doc.shareToken === "string" ? doc.shareToken : null;
    if (existingToken) {
      const cur = await deps.db.collection("shares").doc(existingToken).get();
      const d = cur.data() as ShareDoc | undefined;
      if (cur.exists && d && !d.revokedAt && d.includeTranscript === input.includeTranscript) {
        logDone("share.create", startedAt, { uid, minuteId: input.minuteId, reused: true });
        return { share: toShareInfo(deps.shareBaseUrl, existingToken, d) };
      }
    }

    const token = newShareToken();
    const share: ShareDoc = {
      uid, minuteId: input.minuteId, includeTranscript: input.includeTranscript,
      createdAt: FieldValue.serverTimestamp() as unknown as Timestamp, revokedAt: null, views: 0,
    };
    const batch = deps.db.batch();
    batch.set(deps.db.collection("shares").doc(token), share);
    if (existingToken) batch.update(deps.db.collection("shares").doc(existingToken), { revokedAt: FieldValue.serverTimestamp() });
    batch.update(ref, { shareToken: token, updatedAt: FieldValue.serverTimestamp() });
    await batch.commit();
    const after = (await deps.db.collection("shares").doc(token).get()).data() as ShareDoc;
    logDone("share.create", startedAt, { uid, minuteId: input.minuteId, rotated: existingToken !== null });
    return { share: toShareInfo(deps.shareBaseUrl, token, after) };
  } catch (err) {
    return rethrow(err, "share.create.failed", { uid, minuteId: input.minuteId });
  }
}

export async function revokeShareLinkHandler(caller: Caller | undefined, raw: unknown, deps: Deps): Promise<RevokeShareLinkOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(RevokeShareLinkInput, raw, deps.minClientVersion);
  try {
    const { ref, doc } = await loadOwnedMinute(deps.db, uid, input.minuteId);
    const token = typeof doc.shareToken === "string" ? doc.shareToken : null;
    if (!token) return {};
    const batch = deps.db.batch();
    batch.update(deps.db.collection("shares").doc(token), { revokedAt: FieldValue.serverTimestamp() });
    batch.update(ref, { shareToken: FieldValue.delete(), updatedAt: FieldValue.serverTimestamp() });
    await batch.commit();
    logDone("share.revoke", startedAt, { uid, minuteId: input.minuteId });
    return {};
  } catch (err) {
    return rethrow(err, "share.revoke.failed", { uid, minuteId: input.minuteId });
  }
}

/** For getMinute: the live link, or null. Tolerates a dangling token. */
export async function shareInfoFor(deps: Deps, doc: { shareToken?: unknown }): Promise<ShareInfo | null> {
  const token = typeof doc.shareToken === "string" ? doc.shareToken : null;
  if (!token) return null;
  const snap = await deps.db.collection("shares").doc(token).get();
  const d = snap.data() as ShareDoc | undefined;
  if (!snap.exists || !d || d.revokedAt) return null;
  return toShareInfo(deps.shareBaseUrl, token, d);
}

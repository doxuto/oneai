import { FieldValue } from "firebase-admin/firestore";
import { onCall, type CallableRequest, HttpsError } from "firebase-functions/v2/https";
import { z } from "zod";
import { liveDeps, type Deps } from "../lib/deps.js";
import { rethrow } from "../lib/errors.js";
import { callerOf, requireCaller, type Caller } from "../lib/handler.js";
import { logDone } from "../lib/logging.js";
import { previewOf } from "../lib/stt/convert.js";
import { parse } from "../lib/validate.js";
import { minutesCol, transcriptPath } from "../minutes/_shared.js";
import { withClient } from "../types/common.js";
import { loadShared } from "./page.js";

export const ImportSharedNoteInput = withClient({ token: z.string().regex(/^[A-Za-z0-9_-]{16,64}$/) }).strict();
export interface ImportSharedNoteOutput { minuteId: string; duplicate: boolean }

/**
 * "Save to my notes" from a share link opened in the app (deep link `/s?t=`).
 * Copies the summary (and the transcript when the owner included it) into
 * the caller's account as a ready note with no audio; no quota is charged
 * because nothing is transcribed. Importing the same link twice returns the
 * first copy. The owner's own link just points back at the owner's note.
 */
export async function importSharedNoteHandler(caller: Caller | undefined, raw: unknown, deps: Deps): Promise<ImportSharedNoteOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(ImportSharedNoteInput, raw, deps.minClientVersion);
  try {
    const loaded = await loadShared(deps, input.token);
    if (!loaded) throw new HttpsError("not-found", "This link is no longer available");
    if (loaded.share.uid === uid) return { minuteId: loaded.share.minuteId, duplicate: true };

    const existing = await minutesCol(deps.db, uid).where("importedFromToken", "==", input.token).limit(1).get();
    if (!existing.empty) return { minuteId: existing.docs[0]!.id, duplicate: true };

    const ref = minutesCol(deps.db, uid).doc();
    const { note, minute } = loaded;
    let tPath: string | null = null;
    if (note.transcript) {
      tPath = transcriptPath(uid, ref.id);
      await deps.bucket.file(tPath).save(JSON.stringify(note.transcript), { contentType: "application/json", resumable: false });
    }
    const batch = deps.db.batch();
    batch.set(ref, {
      title: note.title,
      iconEmoji: note.iconEmoji,
      sourceType: note.sourceType,
      contentKind: typeof minute.contentKind === "string" ? minute.contentKind : null,
      status: "ready",
      statusUpdatedAt: FieldValue.serverTimestamp(),
      failure: null,
      durationSeconds: typeof minute.durationSeconds === "number" ? minute.durationSeconds : null,
      sourcePath: null,
      sourceState: "none",
      languageCode: typeof minute.languageCode === "string" ? minute.languageCode : null,
      summaryLanguage: typeof minute.summaryLanguage === "string" ? minute.summaryLanguage : null,
      template: typeof minute.template === "string" ? minute.template : "auto",
      keywords: [],
      description: null,
      tagIds: [],
      summary: note.summary,
      transcriptPath: tPath,
      transcriptPreview: note.transcript ? previewOf(note.transcript.text) : null,
      importedFromToken: input.token,
      importedFromUid: loaded.share.uid,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });
    if (note.speakers.length > 0) {
      batch.set(ref.collection("artifacts").doc("speakers"), { kind: "speakers", data: { speakers: note.speakers }, importedAt: FieldValue.serverTimestamp() });
    }
    await batch.commit();
    logDone("share.import", startedAt, { uid, from: loaded.share.uid, minuteId: ref.id, withTranscript: tPath !== null });
    return { minuteId: ref.id, duplicate: false };
  } catch (err) {
    return rethrow(err, "share.import.failed", { uid });
  }
}

export const importSharedNote = onCall(
  { enforceAppCheck: true, memory: "256MiB", timeoutSeconds: 60, maxInstances: 10 },
  (request: CallableRequest<unknown>) => importSharedNoteHandler(callerOf(request), request.data, liveDeps()),
);

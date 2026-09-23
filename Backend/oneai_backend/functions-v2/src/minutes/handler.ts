import { HttpsError } from "firebase-functions/v2/https";
import { FieldValue, Timestamp, type Query } from "firebase-admin/firestore";
import { decodeCursor, encodeCursor } from "../lib/cursor.js";
import type { Deps } from "../lib/deps.js";
import { mapFirestoreError, rethrow } from "../lib/errors.js";
import { requireCaller, type Caller } from "../lib/handler.js";
import { log, logDone } from "../lib/logging.js";
import { parse } from "../lib/validate.js";
import { shareInfoFor } from "../share/handler.js";
import { contentTypeMatches, loadOwnedMinute, minutePrefix, minuteRef, minutesCol, presentArtifactKinds, safeFileName, sourcePath, tagsCol, toCalendarEvents, toMinuteDetail, toMinuteSummary, toSpeakers, toTranscript } from "./_shared.js";
import {
  CreateMinuteInput,
  DeleteMinuteInput,
  GetMinuteInput,
  ListMinutesInput,
  MAX_SOURCE_BYTES,
  UpdateMinuteInput,
  type CreateMinuteOutput,
  type DeleteMinuteOutput,
  type GetMinuteOutput,
  type ListMinutesOutput,
  type UpdateMinuteOutput,
} from "./types.js";

// ---------------------------------------------------------------- create

export async function createMinuteHandler(
  caller: Caller | undefined,
  raw: unknown,
  deps: Deps,
): Promise<CreateMinuteOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(CreateMinuteInput, raw, deps.minClientVersion);

  if (!contentTypeMatches(input.sourceType, input.contentType)) {
    throw new HttpsError("invalid-argument", "Content type does not match source type", {
      field: "contentType",
    });
  }

  try {
    const ref = minutesCol(deps.db, uid).doc();
    const fileName = safeFileName(input.fileName);
    const path = sourcePath(uid, ref.id, fileName);
    const title = fileName.replace(/\.[^.]+$/, "") || "Untitled";

    await ref.set({
      title,
      iconEmoji: null,
      sourceType: input.sourceType,
      contentKind: null,
      status: "uploading",
      statusUpdatedAt: FieldValue.serverTimestamp(),
      failure: null,
      durationSeconds: null,
      sourcePath: path,
      sourceContentType: input.contentType,
      sourceSizeBytes: input.sizeBytes,
      languageCode: null,
      languageProbability: null,
      summaryLanguage: null,
      keywords: [],
      description: null,
      tagIds: [],
      summary: null,
      transcriptPath: null,
      transcriptPreview: null,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    logDone("minute.created", startedAt, { uid, minuteId: ref.id, sourceType: input.sourceType });
    return {
      minuteId: ref.id,
      upload: { path, contentType: input.contentType, maxSizeBytes: MAX_SOURCE_BYTES },
    };
  } catch (err) {
    return rethrow(err, "minute.create.failed", { uid });
  }
}

// ---------------------------------------------------------------- list

export async function listMinutesHandler(
  caller: Caller | undefined,
  raw: unknown,
  deps: Deps,
): Promise<ListMinutesOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(ListMinutesInput, raw, deps.minClientVersion);

  try {
    let q: Query = minutesCol(deps.db, uid);
    if (input.tagIds && input.tagIds.length > 0) {
      q = q.where("tagIds", "array-contains-any", input.tagIds);
    }
    // Tie-break on document id so the cursor is total-ordered.
    q =
      input.sort === "titleAsc"
        ? q.orderBy("title", "asc").orderBy("__name__", "asc")
        : q.orderBy("createdAt", "desc").orderBy("__name__", "desc");

    if (input.cursor) {
      const parts = decodeCursor(input.cursor);
      if (parts.length !== 2 || typeof parts[1] !== "string") {
        throw new HttpsError("invalid-argument", "Invalid cursor");
      }
      const [key, id] = parts;
      if (input.sort === "titleAsc") {
        if (typeof key !== "string") throw new HttpsError("invalid-argument", "Invalid cursor");
        q = q.startAfter(key, id);
      } else {
        if (typeof key !== "number") throw new HttpsError("invalid-argument", "Invalid cursor");
        q = q.startAfter(Timestamp.fromMillis(key), id);
      }
    }

    // Fetch one extra to know whether a next page exists.
    const snap = await q.limit(input.limit + 1).get();
    const docs = snap.docs.slice(0, input.limit);
    const items = docs.map((d) => toMinuteSummary(d.id, d.data()));

    let nextCursor: string | null = null;
    if (snap.docs.length > input.limit) {
      const last = docs[docs.length - 1];
      const data = last?.data() ?? {};
      if (input.sort === "titleAsc") {
        nextCursor = encodeCursor([typeof data.title === "string" ? data.title : "", last?.id ?? ""]);
      } else {
        const ts = data.createdAt as Timestamp | undefined;
        nextCursor = encodeCursor([ts ? ts.toMillis() : 0, last?.id ?? ""]);
      }
    }

    logDone("minute.list", startedAt, { uid, count: items.length, sort: input.sort });
    return { items, nextCursor };
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    // A missing composite index surfaces as gRPC 9 with the console URL in the
    // message. v1 swallowed this and returned an empty list; we surface it.
    const mapped = mapFirestoreError(err, { uid, op: "minute.list" });
    if (mapped.code === "failed-precondition") {
      log.error("minute.list.index_missing", { uid, error: String(err) });
    }
    throw mapped;
  }
}

// ---------------------------------------------------------------- get

export async function getMinuteHandler(
  caller: Caller | undefined,
  raw: unknown,
  deps: Deps,
): Promise<GetMinuteOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(GetMinuteInput, raw, deps.minClientVersion);

  try {
    const { ref, snap, doc } = await loadOwnedMinute(deps.db, uid, input.minuteId);

    // One read of the whole artifacts subcollection (≤6 small docs) instead of
    // one get per kind: speakers + calendar events come back in it, and its
    // ids tell the app which tabs already exist.
    const [artifacts, transcript, share] = await Promise.all([
      ref.collection("artifacts").get(),
      readTranscript(deps, doc.transcriptPath ?? null),
      shareInfoFor(deps, doc),
    ]);
    const byKind = new Map(artifacts.docs.map((d) => [d.id, d.data() as { data?: unknown }]));

    const minute = toMinuteDetail(snap.id, snap.data(), {
      transcript,
      speakers: toSpeakers(byKind.get("speakers")?.data),
      calendarEvents: toCalendarEvents(byKind.get("calendarEvents")?.data),
      availableArtifacts: presentArtifactKinds(byKind.keys()),
      share,
    });
    logDone("minute.get", startedAt, { uid, minuteId: input.minuteId, status: minute.status });
    return { minute };
  } catch (err) {
    return rethrow(err, "minute.get.failed", { uid, minuteId: input.minuteId });
  }
}

async function readTranscript(deps: Deps, path: string | null) {
  if (!path) return null;
  try {
    const [buf] = await deps.bucket.file(path).download();
    return toTranscript(JSON.parse(buf.toString("utf8")));
  } catch (err) {
    // A note can be `ready` while its transcript file is briefly missing
    // (sweep, partial write). Report null rather than failing the whole read.
    log.warn("minute.transcript.unreadable", { path, error: String(err) });
    return null;
  }
}

// ---------------------------------------------------------------- update

export async function updateMinuteHandler(
  caller: Caller | undefined,
  raw: unknown,
  deps: Deps,
): Promise<UpdateMinuteOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(UpdateMinuteInput, raw, deps.minClientVersion);

  try {
    const { ref } = await loadOwnedMinute(deps.db, uid, input.minuteId);

    const patch: Record<string, unknown> = { updatedAt: FieldValue.serverTimestamp() };
    if (input.title !== undefined) patch.title = input.title.trim();
    if (input.iconEmoji !== undefined) patch.iconEmoji = input.iconEmoji;
    if (input.pinned !== undefined) {
      patch.pinned = input.pinned;
      patch.pinnedAt = input.pinned ? FieldValue.serverTimestamp() : null;
    }
    if (input.tagIds !== undefined) {
      const unique = [...new Set(input.tagIds)];
      if (unique.length > 0) {
        const found = await Promise.all(unique.map((t) => tagsCol(deps.db, uid).doc(t).get()));
        const missing = unique.filter((_, i) => !found[i]?.exists);
        if (missing.length > 0) {
          throw new HttpsError("invalid-argument", "Unknown tag", {
            field: "tagIds",
            issues: missing.map((m) => ({ path: "tagIds", message: `tag ${m} does not exist` })),
          });
        }
      }
      patch.tagIds = unique;
    }

    await ref.update(patch);
    const after = await ref.get();
    logDone("minute.updated", startedAt, { uid, minuteId: input.minuteId });
    return { minute: toMinuteSummary(after.id, after.data()) };
  } catch (err) {
    return rethrow(err, "minute.update.failed", { uid, minuteId: input.minuteId });
  }
}

// ---------------------------------------------------------------- delete

export async function deleteMinuteHandler(
  caller: Caller | undefined,
  raw: unknown,
  deps: Deps,
): Promise<DeleteMinuteOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(DeleteMinuteInput, raw, deps.minClientVersion);

  try {
    const { doc } = await loadOwnedMinute(deps.db, uid, input.minuteId);
    const ref = minuteRef(deps.db, uid, input.minuteId);

    // A live share link dies with the note (the page also 404s on a missing note).
    if (typeof doc.shareToken === "string") {
      await deps.db.collection("shares").doc(doc.shareToken).delete().catch(() => undefined);
    }
    // Firestore first so a retry after a storage failure still sees the doc gone.
    await deps.db.recursiveDelete(ref);
    try {
      await deps.bucket.deleteFiles({ prefix: minutePrefix(uid, input.minuteId) });
    } catch (err) {
      // sweepOrphanFiles picks these up; do not fail the user's delete.
      log.warn("minute.delete.storage_failed", { uid, minuteId: input.minuteId, error: String(err) });
    }

    logDone("minute.deleted", startedAt, { uid, minuteId: input.minuteId });
    return {};
  } catch (err) {
    return rethrow(err, "minute.delete.failed", { uid, minuteId: input.minuteId });
  }
}

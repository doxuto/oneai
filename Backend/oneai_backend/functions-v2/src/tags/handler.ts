import { HttpsError } from "firebase-functions/v2/https";
import { FieldValue, type Firestore, type Transaction } from "firebase-admin/firestore";
import type { Deps } from "../lib/deps.js";
import { rethrow } from "../lib/errors.js";
import { requireCaller, type Caller } from "../lib/handler.js";
import { logDone } from "../lib/logging.js";
import { parse } from "../lib/validate.js";
import { minutesCol, tagsCol } from "../minutes/_shared.js";
import { nameKey, toTagOutput } from "./_shared.js";
import {
  CreateTagInput,
  DeleteTagInput,
  ListTagsInput,
  UpdateTagInput,
  type CreateTagOutput,
  type DeleteTagOutput,
  type ListTagsOutput,
  type UpdateTagOutput,
} from "./types.js";

/** Inside a transaction so two concurrent creates of the same name cannot both pass. */
async function assertNameFree(
  tx: Transaction,
  db: Firestore,
  uid: string,
  key: string,
  exceptId?: string,
): Promise<void> {
  const dup = await tx.get(tagsCol(db, uid).where("nameLower", "==", key).limit(2));
  const clash = dup.docs.find((d) => d.id !== exceptId);
  if (clash) {
    throw new HttpsError("already-exists", "A tag with this name already exists", { field: "name" });
  }
}

export async function createTagHandler(caller: Caller | undefined, raw: unknown, deps: Deps): Promise<CreateTagOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(CreateTagInput, raw, deps.minClientVersion);
  const key = nameKey(input.name);

  try {
    const ref = tagsCol(deps.db, uid).doc();
    await deps.db.runTransaction(async (tx) => {
      await assertNameFree(tx, deps.db, uid, key);
      tx.create(ref, {
        name: input.name.trim(),
        nameLower: key,
        minuteCount: 0,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    const snap = await ref.get();
    logDone("tag.created", startedAt, { uid, tagId: ref.id });
    return { tag: toTagOutput(ref.id, snap.data()) };
  } catch (err) {
    return rethrow(err, "tag.create.failed", { uid });
  }
}

export async function listTagsHandler(caller: Caller | undefined, raw: unknown, deps: Deps): Promise<ListTagsOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  parse(ListTagsInput, raw, deps.minClientVersion);
  try {
    const snap = await tagsCol(deps.db, uid).orderBy("nameLower", "asc").limit(500).get();
    logDone("tag.list", startedAt, { uid, count: snap.size });
    return { items: snap.docs.map((d) => toTagOutput(d.id, d.data())) };
  } catch (err) {
    return rethrow(err, "tag.list.failed", { uid });
  }
}

export async function updateTagHandler(caller: Caller | undefined, raw: unknown, deps: Deps): Promise<UpdateTagOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(UpdateTagInput, raw, deps.minClientVersion);
  const key = nameKey(input.name);

  try {
    const ref = tagsCol(deps.db, uid).doc(input.tagId);
    await deps.db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (!snap.exists) throw new HttpsError("not-found", "Tag not found");
      await assertNameFree(tx, deps.db, uid, key, input.tagId);
      tx.update(ref, { name: input.name.trim(), nameLower: key, updatedAt: FieldValue.serverTimestamp() });
    });
    const after = await ref.get();
    logDone("tag.updated", startedAt, { uid, tagId: input.tagId });
    return { tag: toTagOutput(after.id, after.data()) };
  } catch (err) {
    return rethrow(err, "tag.update.failed", { uid, tagId: input.tagId });
  }
}

export async function deleteTagHandler(caller: Caller | undefined, raw: unknown, deps: Deps): Promise<DeleteTagOutput> {
  const startedAt = Date.now();
  const { uid } = requireCaller(caller);
  const input = parse(DeleteTagInput, raw, deps.minClientVersion);

  try {
    const ref = tagsCol(deps.db, uid).doc(input.tagId);
    const snap = await ref.get();
    if (!snap.exists) throw new HttpsError("not-found", "Tag not found");

    // Detach from every note first, in batches of 500 (the Firestore limit).
    let affected = 0;
    for (;;) {
      const page = await minutesCol(deps.db, uid)
        .where("tagIds", "array-contains", input.tagId)
        .limit(500)
        .get();
      if (page.empty) break;
      const batch = deps.db.batch();
      for (const d of page.docs) {
        batch.update(d.ref, { tagIds: FieldValue.arrayRemove(input.tagId), updatedAt: FieldValue.serverTimestamp() });
      }
      await batch.commit();
      affected += page.size;
      if (page.size < 500) break;
    }

    await ref.delete();
    logDone("tag.deleted", startedAt, { uid, tagId: input.tagId, affected });
    return { affectedMinuteCount: affected };
  } catch (err) {
    return rethrow(err, "tag.delete.failed", { uid, tagId: input.tagId });
  }
}

import type { DocumentData, Firestore } from "firebase-admin/firestore";
import { FieldValue } from "firebase-admin/firestore";
import { minutesCol, tagsCol } from "./_shared.js";

function tagIdsOf(d: DocumentData | undefined): string[] {
  const v = d?.tagIds;
  return Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : [];
}

/**
 * Pure enough to test directly against the emulator: given the before/after
 * of one minute write, recompute the user's note count and the count of every
 * tag whose membership changed. Returns the tag ids it touched.
 */
export async function recountAfterMinuteWrite(
  db: Firestore,
  uid: string,
  before: DocumentData | undefined,
  after: DocumentData | undefined,
): Promise<string[]> {
  const beforeTags = new Set(tagIdsOf(before));
  const afterTags = new Set(tagIdsOf(after));
  const changed = [...new Set([...beforeTags, ...afterTags])].filter(
    (t) => beforeTags.has(t) !== afterTags.has(t),
  );

  const created = before === undefined && after !== undefined;
  const deleted = before !== undefined && after === undefined;

  const writes: Promise<unknown>[] = [];

  if (created || deleted) {
    const total = (await minutesCol(db, uid).count().get()).data().count;
    writes.push(
      db.doc(`users/${uid}`).set(
        { minuteCount: total, updatedAt: FieldValue.serverTimestamp() },
        { merge: true },
      ),
    );
  }

  for (const tagId of changed) {
    const ref = tagsCol(db, uid).doc(tagId);
    writes.push(
      (async () => {
        const snap = await ref.get();
        if (!snap.exists) return; // tag already deleted; nothing to maintain
        const n = (await minutesCol(db, uid).where("tagIds", "array-contains", tagId).count().get()).data().count;
        await ref.update({ minuteCount: n });
      })(),
    );
  }

  await Promise.all(writes);
  return changed;
}

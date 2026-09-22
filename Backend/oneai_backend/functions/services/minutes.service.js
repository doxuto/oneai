const { db, bucket } = require('../config/config-firebase');

async function readJsonFromGcsUri(gcsUri) {
    try {
        const [, , bucketName, ...filePathArr] = gcsUri.split('/');
        const filePath = filePathArr.join('/');
        const file = bucket.file(filePath);
        const [contents] = await file.download();
        return JSON.parse(contents.toString());
    } catch (err) {
        console.error(`❌ Failed to read JSON from GCS: ${gcsUri}`, err.message);
        return null;
    }
}
const deleteMinuteFiles = async (userId, minuteId) => {
    const prefix = `user_uploads/${userId}/${minuteId}/`; // matches your folder layout
    console.log(`🧹 [deleteMinute] Deleting Cloud Storage files with prefix "${prefix}"`);

    // bucket is imported from config-firebase
    await bucket.deleteFiles({ prefix });
    console.log("✅ [deleteMinute] Storage cleanup complete");
};

/**
 * Upsert minute document + optional metadata sub-documents.
 *
 * @param {string}  userId
 * @param {string}  minuteId
 * @param {?object} transcription   – raw transcription JSON (optional)
 * @param {?object} summary         – summary object (may include speakers,
 *                                    calendarEvents, quiz, flashcards, mindmap)
 * @param {object}  data            – main minute doc (metadata)
 * @param {object}  options         – { merge?: boolean }
 *
 * @returns {object} baseData that was written to the main minute doc
 */
exports.upsertMinute = async (
  userId,
  minuteId,
  transcription,
  summary,
  data,
  { merge = true } = {}
) => {
  console.log(`📥 [upsertMinute] Upserting minute ${minuteId} for user ${userId}`);

  /* ────────── 0. Firestore refs ─────────────────────────────────────── */
  const minuteRef = db
    .collection("users").doc(userId)
    .collection("minutes").doc(minuteId);

  /* ────────── 1. Main minute doc ────────────────────────────────────── */
  const baseData = { ...data, updatedAt: new Date() };
  await minuteRef.set(baseData, { merge });
  console.log("ℹ️  Main minute doc written/merged");

  /* helper: metadata/{docId} */
  const metaDoc = id => minuteRef.collection("metadata").doc(id);

  /* ────────── 2. Transcription (overwrite) ──────────────────────────── */
  if (transcription) {
    await metaDoc("transcription").set(transcription);
    console.log("📝  Transcription stored");
  }

  /* ────────── 3. Summary (strip nested extras) ──────────────────────── */
  if (summary) {
    const {
      speakers,
      calendarEvents,
      quiz,
      flashcards,
      mindmap,
      ...cleanSummary
    } = summary;

    // summary without nested blocks
    await metaDoc("summary").set(cleanSummary);
    console.log("🗒  Summary stored (nested blocks stripped)");

    /* ---- 3a. Speakers ------------------------------------------------ */
    if (speakers) {
      await metaDoc("speakers").set(speakers);
      console.log("🎙  Speakers stored");
    }

    /* ---- 3b. Calendar events ---------------------------------------- */
    if (calendarEvents) {
      await metaDoc("calendarEvents").set({ calendarEvents });
      console.log("📅  Calendar events stored");
    }

    /* ---- 3c. Quiz ---------------------------------------------------- */
    if (quiz) {
      await metaDoc("quiz").set({ quiz });
      console.log("❓  Quiz stored");
    }

    /* ---- 3d. Flashcards --------------------------------------------- */
    if (flashcards) {
      await metaDoc("flashcards").set({ flashcards });
      console.log("🃏  Flashcards stored");
    }

    /* ---- 3e. Mind-map ----------------------------------------------- */
    if (mindmap) {
      await metaDoc("mindmap").set(mindmap);
      console.log("🗺️  Mind-map stored");
    }
  }

  console.log(`✅ [upsertMinute] Finished ${minuteId}`);
  return baseData;
};

/**
 * ✅ Add new minutes
 */
exports.addMinutes = async (userId, {
    title = '',
    timestamp = '',
    duration = '',
    iconAsset = '',
    tags = []
}) => {
    console.log(`📥 [addMinutes] Add minutes for user: ${userId}`);

    const newRecord = {
        title,
        timestamp,
        duration,
        iconAsset,
        tags,
        createdAt: new Date().toISOString(),
    };

    await db.collection('users').doc(userId).collection('minutes').add(newRecord);

    console.log(`✅ [addMinutes] Added new minutes for user: ${userId}`);
    return newRecord;
};

/**
 * ✅ Get paginated minutes
 */
exports.getMinutes = async ({
    userId,
    limit = 10,
    sort = 'createdAt:desc',
    tags = '',
    search = '',
    startDate = '',
    endDate = '',
    startAfterDocId = null
}) => {
    const startTime = Date.now();
    console.log('📥 [getMinutes] Start →', {
        userId,
        limit,
        sort,
        tags,
        search,
        startDate,
        endDate,
        startAfterDocId
    });

    let result;
    try {
        result = await queryCollectionWithCursorPagination({
            userId,
            limit,
            sort,
            tags,
            search,
            startDate,
            endDate,
            startAfterDocId
        });
    } catch (err) {
        console.error('❌ [getMinutes] Error during query:', err);
        throw err;
    }

    const durationMs = Date.now() - startTime;
    console.log(`✅ [getMinutes] ${result.data.length} records | hasNext: ${result.hasNextPage} | nextCursor: ${result.nextPageCursor} | ⏱ ${durationMs}ms`);

    return result;
};

/**
 * 🔍 Fetch a single minute by ID
 * • Flattens metadata (flashcards, quiz, mindmap, shortQuestions) to top level
 * • Optionally loads transcription and summary JSON from GCS
 *
 * @param {string} userId
 * @param {string} minuteId
 * @returns {Promise<object|null>}
 */
exports.getMinuteById = async (userId, minuteId) => {
    console.log(`📥 [getMinuteById] userId=${userId}, minuteId=${minuteId}`);

    if (!userId || !minuteId) throw new Error("Missing userId or minuteId");

    const minuteRef = db
        .collection("users").doc(userId)
        .collection("minutes").doc(minuteId);

    const minuteSnap = await minuteRef.get();
    if (!minuteSnap.exists) {
        console.warn("⚠️ [getMinuteById] Minute not found");
        return null;
    }

    /** Raw Firestore data */
    const data = minuteSnap.data();
    /** Final result object */
    const result = { id: minuteId, ...data };



    /* ──────────────── 1. Load metadata docs and flatten ──────────────── */
    const metadataConfigs = [
        {
            docId: "summary",
            resultField: "summary",
            pick: d => d.summary ?? d
        },
        {
            docId: "transcription",
            resultField: "transcription",
            pick: d => d.transcription ?? d
        },
        // {
        //     docId: "flashcards",
        //     resultField: "flashcards",
        //     pick: d => d.flashcards ?? d
        // },
        // {
        //     docId: "quiz",
        //     resultField: "quiz",
        //     pick: d => d.quiz ?? d
        // },
        // {
        //     docId: "mindmap",
        //     resultField: "mindmap",
        //     pick: d => d.mindmap ?? d
        // },
        {
            docId: "shortQuestions",
            resultField: "shortQuestions",
            pick: d => d.short_questions ?? d
        },
        // {
        //     docId: "calendarEvents",
        //     resultField: "calendarEvents",
        //     pick: d => d.calendarEvents ?? d
        // },
        {
            docId: "speakers",
            resultField: "speakers",
            pick: d => d.speakers ?? d
        }
    ];

    const metaPromises = metadataConfigs.map(async ({ docId, resultField, pick }) => {
        try {
            const snap = await minuteRef.collection("metadata").doc(docId).get();
            if (snap.exists) {
                result[resultField] = pick(snap.data());
                console.log(`✅ Metadata loaded → ${resultField}`);
            } else {
                console.log(`ℹ️ No metadata found for ${resultField}`);
            }
        } catch (err) {
            console.error(`❌ Error loading ${resultField}:`, err.message);
        }
    });

    await Promise.all(metaPromises);

    /* ──────────────── 2. Load transcription & summary from GCS ──────────────── */
    const gcsJsonFiles = [
        { firestoreKey: "transcriptionUri", resultField: "transcription" },
        { firestoreKey: "summaryUri", resultField: "summary" },
    ];

    for (const { firestoreKey, resultField } of gcsJsonFiles) {
        if (!data[firestoreKey]) continue;

        if (result[resultField] !== undefined) {
            console.log(`ℹ️ Skip loading ${resultField} from GCS (already present)`);
            continue;
        }

        try {
            console.log(`📁 Loading ${resultField} from ${data[firestoreKey]}`);
            const json = await readJsonFromGcsUri(data[firestoreKey]);
            result[resultField] = json;
            console.log(`✅ ${resultField} loaded successfully`);
        } catch (err) {
            console.error(`❌ Failed to load ${resultField}:`, err.message);
        }
    }

    /* ──────────────── Done ──────────────── */
    return result;
};

/**
 * ✅ Validate tag IDs exist in Firestore
 */
const filterValidTagIds = async (userId, tagIds) => {
    const tagRef = db.collection('tags').doc(userId).collection('tagItems');
    const snapshots = await Promise.all(tagIds.map(id => tagRef.doc(id).get()));
    return tagIds.filter((_, idx) => snapshots[idx].exists);
};
/**
 * ✅ Update minute by Id
 */
exports.updateMinute = async (userId, minuteId, { title, iconAsset, tags, summaryText, transcription }) => {
    console.log(`📥 [updateMinute] userId=${userId}, minuteId=${minuteId}`);

    const docRef = db.collection('users').doc(userId).collection('minutes').doc(minuteId);
    const doc = await docRef.get();

    if (!doc.exists) {
        console.warn(`⚠️ [updateMinute] Minute not found: ${minuteId}`);
        return null;
    }

    const updates = {};

    if (title !== undefined) updates.title = title;
    if (iconAsset !== undefined) updates.iconAsset = iconAsset;
    if (summaryText !== undefined) updates.summaryText = summaryText;
    if (transcription !== undefined) updates.transcription = transcription;

    if (Array.isArray(tags)) {
        const validTags = await filterValidTagIds(userId, tags);
        updates.tags = validTags;
        console.log(`🔎 [updateMinute] Valid tags: ${validTags.join(', ')}`);
    }

    if (Object.keys(updates).length === 0) {
        console.warn("⚠️ [updateMinute] No valid fields provided to update");
        return {};
    }

    updates.updatedAt = new Date();

    await docRef.set(updates, { merge: true });

    console.log(`✅ [updateMinute] Updated minute ${minuteId}`);
    return { minuteId, ...updates };
};

/**
 * 🗑️  Delete a minute and ALL nested data
 * @param {string} userId
 * @param {string} minuteId
 * @returns {Promise<boolean>} true if deleted, false if not found
 */
exports.deleteMinute = async (userId, minuteId) => {
    console.log(`📥 [deleteMinute] userId=${userId}, minuteId=${minuteId}`);

    const minuteRef = db.collection("users").doc(userId)
        .collection("minutes").doc(minuteId);

    const snap = await minuteRef.get();
    if (!snap.exists) {
        console.warn(`⚠️ [deleteMinute] Minute not found: ${minuteId}`);
        return false;
    }

    try {
        await db.recursiveDelete(minuteRef);
        console.log("✅ Firestore documents removed");

        /* 2️⃣ Cloud Storage cleanup */
        await deleteMinuteFiles(userId, minuteId);

        console.log(`✅ [deleteMinute] Minute ${minuteId} fully removed`);
        return true;
    } catch (err) {
        console.error("❌ [deleteMinute] Error:", err);
        throw err;
    }
};
/**
 * 🔎 Helper: Pagination query with cursor (log-optimized)
 */
const queryCollectionWithCursorPagination = async ({
    userId,
    sort = "createdAt:desc",
    limit = 10,
    tags = "",
    search = "",
    startAfterDocId = null,
    startDate = "",
    endDate = ""
}) => {
    try {
        const [field, order] = sort.split(":");
        let query = db.collection("users").doc(userId).collection("minutes");

        console.log(`📥 [queryCollectionWithCursorPagination]`, {
            userId,
            sort,
            limit,
            tags,
            search,
            startAfterDocId,
            startDate,
            endDate
        });

        // 🔎 Tags
        const tagsArray = tags.split(",").map(tag => tag.trim()).filter(Boolean);
        if (tagsArray.length) {
            query = query.where("tags", "array-contains-any", tagsArray);
        }

        // 🔎 Title search
        if (search.trim()) {
            query = query
                .where("title", ">=", search)
                .where("title", "<=", search + "\uf8ff");
        }

        // 🔎 Date range
        if (startDate && !isNaN(Date.parse(startDate))) {
            query = query.where("createdAt", ">=", new Date(startDate));
        }
        if (endDate && !isNaN(Date.parse(endDate))) {
            query = query.where("createdAt", "<=", new Date(endDate));
        }

        // 🔃 Sort
        query = query.orderBy(field, order);

        // 🧭 startAfter
        if (startAfterDocId) {
            const startAfterDoc = await db
                .collection("users")
                .doc(userId)
                .collection("minutes")
                .doc(startAfterDocId)
                .get();

            const cursorValue = startAfterDoc.data()?.[field];
            if (startAfterDoc.exists && cursorValue !== undefined) {
                query = query.startAfter(cursorValue);
            } else {
                console.warn(`⚠️ Cannot apply startAfter — missing field "${field}" or document not found`);
            }
        }

        // 🧮 Pagination
        const snapshot = await query.limit(limit + 1).get();

        const docs = snapshot.docs;
        const hasNextPage = docs.length > limit;
        const paginatedDocs = hasNextPage ? docs.slice(0, limit) : docs;

        const results = paginatedDocs.map(doc => ({
            id: doc.id,
            ...doc.data()
        }));

        const nextPageCursor = hasNextPage ? docs[limit].id : null;

        console.log(`✅ Fetched ${results.length} documents. hasNextPage: ${hasNextPage}`);

        return {
            data: results,
            nextPageCursor,
            hasNextPage
        };

    } catch (error) {
        console.error("❌ queryCollectionWithCursorPagination error:", error);
        return {
            data: [],
            nextPageCursor: null,
            hasNextPage: false
        };
    }
};
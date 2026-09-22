const { db } = require('../config/config-firebase');
const { successResponse, errorResponse, notFoundResponse } = require('../utils/responseHelper');

const collectionName = "tags";

/**
 * ✅ Create a new tag under a user's tagItems subcollection (no duplicates allowed)
 */

exports.createTag = async (req, res) => {
  const userId = req.user?.user_id;
  const { name } = req.body;
  console.debug('📌 [createTag] userId:', userId, 'name:', name);

  if (!userId || !name) {
    return res.status(400).json(errorResponse("Missing userId or tag name"));
  }

  try {
    // 🔧 Normalize tag name: lowercase + replace spaces with underscores
    const normalized = name.trim().toLowerCase().replace(/\s+/g, '_');

    // 🔍 Check for duplicate tag name
    const snapshot = await db
      .collection(collectionName)
      .doc(userId)
      .collection('tagItems')
      .where('name_lower', '==', normalized)
      .get();

    if (!snapshot.empty) {
      console.warn(`⚠️ [createTag] Duplicate tag name detected: '${name}'`);
      return res.status(409).json(errorResponse("Tag name already exists."));
    }

    // ✅ Create tag document with normalized name
    const tagRef = db
      .collection(collectionName)
      .doc(userId)
      .collection('tagItems')
      .doc();

    await tagRef.set({
      name,
      name_lower: normalized
    });

    console.debug('✅ [createTag] Tag created:', tagRef.id);
    return successResponse(res, { id: tagRef.id, name }, "Tag created successfully");
  } catch (err) {
    console.error('🔥 [createTag] Error:', err);
    return res.status(500).json(errorResponse(err.message));
  }
};

/**
 * ✅ Update a tag's name under a user's tagItems subcollection
 */
exports.updateTag = async (req, res) => {
  const userId = req.user?.user_id;
  const tagId = req.params.id;
  const { name } = req.body;

  console.debug('📌 [updateTag] userId:', userId, 'tagId:', tagId, 'new name:', name);

  if (!userId || !tagId || !name) {
    return res.status(400).json(errorResponse("Missing userId, tagId, or new name"));
  }

  try {
    // 🔧 Normalize new tag name: lowercase + replace spaces with underscores
    const normalized = name.trim().toLowerCase().replace(/\s+/g, '_');

    // 🔍 Check for duplicate name among other tags
    const duplicateSnapshot = await db
      .collection(collectionName)
      .doc(userId)
      .collection('tagItems')
      .where('name_lower', '==', normalized)
      .get();

    const isDuplicate = duplicateSnapshot.docs.some(doc => doc.id !== tagId);

    if (isDuplicate) {
      console.warn(`⚠️ [updateTag] Duplicate tag name detected: '${name}'`);
      return res.status(409).json(errorResponse("Tag name already exists."));
    }

    // ✅ Update tag document
    const tagRef = db
      .collection(collectionName)
      .doc(userId)
      .collection('tagItems')
      .doc(tagId);

    const doc = await tagRef.get();
    if (!doc.exists) {
      return notFoundResponse(res, "Tag not found");
    }

    await tagRef.update({
      name,
      name_lower: normalized
    });

    console.debug(`✅ [updateTag] Updated tag ${tagId} to name: ${name}`);
    return successResponse(res, { tagId, name }, "Tag updated successfully");
  } catch (err) {
    console.error('🔥 [updateTag] Error:', err);
    return res.status(500).json(errorResponse(err.message));
  }
};

/**
 * ✅ Get all tags under a user's tagItems subcollection
 */
exports.getAll = async (req, res) => {
  const userId = req.user?.user_id;
  console.debug('📌 [getAll] userId:', userId);

  if (!userId) {
    return res.status(400).json(errorResponse("Missing userId"));
  }

  try {
    const snapshot = await db
      .collection(collectionName)
      .doc(userId)
      .collection('tagItems')
      .get();

    const tags = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));

    console.debug(`✅ [getAll] Fetched ${tags.length} tags for user ${userId}`);
    return successResponse(res, { tags });
  } catch (err) {
    console.error('🔥 [getAll] Error:', err);
    return res.status(500).json(errorResponse(err.message));
  }
};

/**
 * ✅ Delete a tag by ID under a user's tagItems subcollection
 */
exports.deleteTag = async (req, res) => {
  const userId = req.user?.user_id;
  const tagId = req.params.id;

  console.debug('📌 [deleteTag] userId:', userId, 'tagId:', tagId);

  if (!userId || !tagId) {
    return res.status(400).json(errorResponse("Missing userId or tagId"));
  }

  try {
    const tagRef = db
      .collection(collectionName)
      .doc(userId)
      .collection('tagItems')
      .doc(tagId);

    const doc = await tagRef.get();
    if (!doc.exists) {
      return notFoundResponse(res, "Tag not found");
    }

    // 🔥 Delete tag from 'tags' collection
    await tagRef.delete();
    console.debug(`✅ [deleteTag] Deleted tag: ${tagId} for user: ${userId}`);

    // 🔁 Remove tagId from all minutes of the user
    const minutesRef = db.collection('users').doc(userId).collection('minutes');
    const snapshot = await minutesRef.where('tags', 'array-contains', tagId).get();

    const batch = db.batch();
    snapshot.forEach((minuteDoc) => {
      const data = minuteDoc.data();
      const newTags = (data.tags || []).filter(t => t !== tagId);
      batch.update(minuteDoc.ref, { tags: newTags });
      console.debug(`↪️ Removed tag ${tagId} from minute ${minuteDoc.id}`);
    });

    await batch.commit();
    console.debug(`✅ [deleteTag] Tag ${tagId} removed from ${snapshot.size} minutes`);

    return successResponse(res, { tagId, affectedMinutes: snapshot.size }, "Tag deleted successfully");
  } catch (err) {
    console.error('🔥 [deleteTag] Error:', err);
    return res.status(500).json(errorResponse(err.message));
  }
};
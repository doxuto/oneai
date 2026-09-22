const admin = require("firebase-admin");
if (!admin.apps.length) admin.initializeApp();
const db = admin.firestore();

// Get minutes with optional filters
exports.getMinutes = async (uid, filters = {}) => {
  let query = db.collection("minutes").where("uid", "==", uid);
  if (filters.tags) {
    query = query.where("tags", "array-contains-any", filters.tags.split(","));
  }
  if (filters.search) {
    // Note: Firestore doesn't support 'contains' well, this is simplified
    query = query.where("title", ">=", filters.search);
  }
  if (filters.startDate) query = query.where("timestamp", ">=", new Date(filters.startDate));
  if (filters.endDate) query = query.where("timestamp", "<=", new Date(filters.endDate));

  const snapshot = await query.limit(parseInt(filters.limit || 20)).get();
  return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
};

exports.getMinuteById = async (uid, id) => {
  const doc = await db.collection("minutes").doc(id).get();
  if (!doc.exists || doc.data().uid !== uid) throw new Error("Not found");
  return { id: doc.id, ...doc.data() };
};

exports.updateMinute = async (uid, id, data) => {
  const ref = db.collection("minutes").doc(id);
  await ref.set({ ...data, uid }, { merge: true });
  const doc = await ref.get();
  return { id: doc.id, ...doc.data() };
};

exports.deleteMinute = async (uid, id) => {
  await db.collection("minutes").doc(id).delete();
  return { success: true };
};

exports.getTags = async (uid) => {
  const snapshot = await db.collection("tags").where("uid", "==", uid).get();
  return snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
};

exports.createTag = async (uid, name) => {
  const ref = await db.collection("tags").add({ uid, name });
  return { id: ref.id, name };
};

exports.deleteTag = async (uid, id) => {
  await db.collection("tags").doc(id).delete();
  return { success: true };
};

exports.getChatHistory = async (minuteId) => {
  const snapshot = await db.collection("minutes").doc(minuteId).collection("chat").orderBy("timestamp").get();
  return snapshot.docs.map(doc => doc.data());
};

exports.saveChatMessage = async (minuteId, message, senderType) => {
  const ref = db.collection("minutes").doc(minuteId).collection("chat").doc();
  const data = { message, senderType, timestamp: new Date().toISOString() };
  await ref.set(data);
  return data;
};

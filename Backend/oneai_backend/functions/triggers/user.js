
const functionsV1 = require("firebase-functions/v1");  
const { db, FieldValue, bucket } = require("../config/config-firebase");
const { beforeUserSignedIn } = require("firebase-functions/v2/identity");

exports.createUserProfile = functionsV1.auth.user().onCreate(async (user) => {
    console.log(`👤 New user: uid=${user.uid}, email=${user.email ?? 'N/A'}, displayName=${user.displayName ?? 'N/A'}`);

    await db.collection('users').doc(user.uid).set({
        uid: user.uid,
        email: user.email ?? null,
        displayName: user.displayName ?? null,
        photoURL: user.photoURL ?? null,
        createdAt: new Date(),
        role: 'user',
        plan: 'free',
        credit: 1
    });

    console.log(`✅ User ${user.uid} profile created`);
});

exports.deleteUserData = functionsV1.auth.user().onDelete(async (user) => {
  const userId = user.uid;
  console.log(`🗑️ Deleting all data for userId=${userId}`);

  try {
    // 1. Delete minutes
    const minutesSnap = await db.collection(`users/${userId}/minutes`).get();
    await Promise.all(minutesSnap.docs.map(doc => doc.ref.delete()));
    console.log(`✅ Deleted minutes`);

    await db.collection("users").doc(userId).delete();
    console.log(`✅ Deleted user document`);

    // 2. Delete tagItems
    const tagItemsRef = db.collection(`tags/${userId}/tagItems`);
    const tagItemsSnap = await tagItemsRef.listDocuments();
    await Promise.all(tagItemsSnap.map(doc => doc.delete()));
    console.log(`✅ Deleted ${tagItemsSnap.length} tagItems`);

    await db.collection("tags").doc(userId).delete();
    console.log(`✅ Deleted tags document`);

  } catch (err) {
    console.error(`❌ Firestore error: ${err.message}`);
  }

  try {
    // 3. Delete storage
    const folderPath = `user_uploads/${userId}`;
    const [files] = await bucket.getFiles({ prefix: folderPath });

    if (files.length > 0) {
      await Promise.all(files.map(file => file.delete()));
      console.log(`✅ Deleted ${files.length} files`);
    } else {
      console.log(`ℹ️ No files found`);
    }
  } catch (err) {
    console.error(`❌ Storage error: ${err.message}`);
  }

  console.log(`🎉 Done deleting user data for userId=${userId}`);
});

/**
 * ✅ Callable function to update lastLoginAt
 * 👉 Call from client after sign-in
 */
exports.updateLastLogin = beforeUserSignedIn(async (event) => {
    const userId = event.data.uid;
    if (!userId) throw new Error("Unauthenticated request");

    console.log(`📥 [updateLastLogin] Updating lastLoginAt for user: ${userId}`);

    // Sử dụng .set() với { merge: true } thay vì .update()
    await db.collection("users").doc(userId).set({
        lastLoginAt: FieldValue.serverTimestamp()
    }, { merge: true });

    console.log(`✅ [updateLastLogin] Updated for user: ${userId}`);
    return { success: true };
});
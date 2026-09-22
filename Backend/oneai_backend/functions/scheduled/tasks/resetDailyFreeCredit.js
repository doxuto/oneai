const { admin, Timestamp }= require("../../config/config-firebase")

const DAILY_FREE_CREDIT = 1;
const USERS_BATCH_SIZE = 500; 


module.exports = async function resetDailyCredit() {
    const db = admin.firestore();
    const usersRef = db.collection("users");
    const snapshot = await usersRef.where("plan", "==", "free").get();

    console.log(`🔁 Found ${snapshot.size} free users`);

    const batches = [];
    let batch = db.batch();
    let count = 0;

    snapshot.docs.forEach((doc) => {
      batch.update(doc.ref, {
        credit: DAILY_FREE_CREDIT,
        dailyCreditUsed: 0,
        lastCreditReset: Timestamp.now(),
      });

      count++;
      if (count === USERS_BATCH_SIZE) {
        batches.push(batch.commit());
        batch = db.batch();
        count = 0;
      }
    });

    if (count > 0) {
      batches.push(batch.commit());
    }

    await Promise.all(batches);
    console.log(`✅ Successfully reset credits for ${snapshot.size} users`);
    return null;
  }

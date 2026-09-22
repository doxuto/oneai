const { db, admin, FieldValue } = require("../config/config-firebase");

/**
 * Checks if a user is allowed to consume a credit based on their plan and credit balance.
 * If allowed, it deducts 1 credit (except for premium users).
 *
 * @param {string} userId - The Firebase user ID
 * @returns {Promise<{allowed: boolean, plan: string, credit: number}>}
 */
async function checkAndConsumeUserCredit(userId) {
  console.log(`🔍 [CreditCheck] Verifying user credit for: ${userId}`);

  const userRef = db.collection("users").doc(userId);
  const userSnap = await userRef.get();

  if (!userSnap.exists) {
    console.error(`❌ [CreditCheck] User not found: ${userId}`);
    throw new Error("User not found in Firestore.");
  }

  const userData = userSnap.data();
  const plan = userData.plan || "free";
  const credit = typeof userData.credit === "number" ? userData.credit : 0;

  console.log(`📋 [CreditCheck] User plan: ${plan}, credit: ${credit}`);

  if (plan === "premium") {
    // Premium users have unlimited usage
    console.log(`💎 [CreditCheck] Premium user — no credit deduction needed.`);
    return { allowed: true, plan, credit };
  }

  if (credit > 0) {
    // Deduct credit safely using atomic increment
    await userRef.update({
      credit: admin.firestore.FieldValue.increment(-1)
    });
    console.log(`✅ [CreditCheck] Credit deducted. Previous: ${credit}, New: ${credit - 1}`);
    return { allowed: true, plan, credit: credit - 1 };
  }

  // Credit exhausted and not on premium plan
  console.warn(`⛔ [CreditCheck] User has no remaining credits.`);
  return { allowed: false, plan, credit };
}

/**
 * Checks if a user is allowed to use a credit based on their plan and current balance.
 *
 * @param {string} userId
 * @returns {Promise<{allowed: boolean, plan: string, credit: number, reason?: string}>}
 */
async function checkUserCanUseCredit(userId) {
  console.log(`🔍 [CreditCheck] Checking user credit for: ${userId}`);

  const userRef = db.collection("users").doc(userId);
  const userSnap = await userRef.get();

  if (!userSnap.exists) {
    console.error(`❌ [CreditCheck] User not found: ${userId}`);
    throw new Error("User not found in Firestore.");
  }

  const userData = userSnap.data();
  const plan = userData.plan || "free";
  const credit = typeof userData.credit === "number" ? userData.credit : 0;
  const dailyCreditUsed = typeof userData.dailyCreditUsed === "number" ? userData.dailyCreditUsed : 0;

  if (plan === "premium") {
    console.log(`💎 [CreditCheck] Premium user — allowed`);
    return { allowed: true, plan, credit };
  }

  if (dailyCreditUsed >= 3) {
    console.warn(`⛔ [CreditCheck] Daily credit limit reached (${dailyCreditUsed}/3)`);
    return { allowed: false, plan, credit, reason: "daily_limit_exceeded" };
  }

  const allowed = credit > 0;
  console.log(`📋 [CreditCheck] Plan: ${plan}, Credit: ${credit}, DailyUsed: ${dailyCreditUsed}, Allowed: ${allowed}`);

  return { allowed, plan, credit };
}

/**
 * Records user credit usage.
 * - Free users: deduct 1 credit and increment usage counters.
 * - Premium users: only increment usage counters.
 *
 * @param {string} userId
 * @returns {Promise<void>}
 */
async function consumeUserCredit(userId) {
  const userRef = db.collection("users").doc(userId);
  const userSnap = await userRef.get();

  if (!userSnap.exists) {
    console.error(`❌ [ConsumeCredit] User not found: ${userId}`);
    throw new Error("User not found in Firestore.");
  }

  const userData = userSnap.data();
  const { plan, credit } = userData;

  const updates = {
    dailyCreditUsed: FieldValue.increment(1),
    totalCreditUsed: FieldValue.increment(1),
  };

  if (plan === "premium") {
    console.log(`💎 [ConsumeCredit] Premium user — just tracking usage.`);
  } else {
    if (typeof credit === "number" && credit > 0) {
      updates.credit = FieldValue.increment(-1);
    } else {
      console.error(`❌ [ConsumeCredit] Free user has no credit left.`);
      throw new Error("Insufficient credit.");
    }
  }

  await userRef.update(updates);

  const dailyUsed = userData.dailyCreditUsed ?? 0;
  const totalUsed = userData.totalCreditUsed ?? 0;

  const remaining = typeof credit === "number" ? credit - 1 : "N/A";

  console.log(`✅ [ConsumeCredit] User: ${userId} — Remaining: ${remaining}, Used today: ${dailyUsed + 1}, Total used: ${totalUsed + 1}`);
}

module.exports = { checkUserCanUseCredit, consumeUserCredit };
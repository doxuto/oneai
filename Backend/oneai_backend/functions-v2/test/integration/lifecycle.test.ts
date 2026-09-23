/** Runs under `npm run test:integration`. The auth triggers' bodies. */
import { getStorage } from "firebase-admin/storage";
import { beforeEach, describe, expect, it } from "vitest";
import { unitDeps, type Deps } from "../../src/lib/deps.js";
import { getMeHandler } from "../../src/users/handler.js";
import { provisionUser, wipeUser } from "../../src/users/lifecycle.js";
import { clearFirestore, fixedNow, testDb } from "../helpers/emulator.js";

const db = testDb();
const bucket = getStorage().bucket("demo-oneai.appspot.com");
const deps: Deps = unitDeps({ db, bucket: bucket as Deps["bucket"], now: fixedNow("2026-09-23T03:00:00.000Z") }); // 10:00 VN
const client = { appVersion: "2.0.0", build: 1, platform: "ios" as const };

async function clearStorage() {
  const [files] = await bucket.getFiles({ prefix: "users/" });
  await Promise.all(files.map((f) => f.delete()));
}

describe("provisionUser (onUserCreated)", () => {
  beforeEach(async () => { await clearFirestore(); await clearStorage(); });

  it("writes the profile and today's quota so getMe works immediately", async () => {
    expect(await provisionUser(deps, { uid: "u1", email: "a@b.c", displayName: "Ana", photoURL: null })).toBe(true);
    const me = await getMeHandler({ uid: "u1", signInProvider: "google.com" }, { client }, deps);
    expect(me.user).toMatchObject({ id: "u1", email: "a@b.c", displayName: "Ana", plan: "free", minuteCount: 0 });
    expect(me.quota).toMatchObject({ used: 0, limit: deps.limits.free.dailyLimit, rewardBonus: 0 });
    const q = (await db.doc("users/u1/quota/2026-09-23").get()).data();
    expect(q?.expiresAt.toDate().toISOString()).toBe("2026-09-26T03:00:00.000Z"); // TTL 3 days
  });

  it("a redelivered trigger never resets an existing user's profile or quota", async () => {
    await provisionUser(deps, { uid: "u1", email: "a@b.c" });
    await db.doc("users/u1").update({ plan: "premium", minuteCount: 4, displayName: "Renamed" });
    await db.doc("users/u1/quota/2026-09-23").update({ used: 1, rewardBonus: 2 });

    expect(await provisionUser(deps, { uid: "u1", email: "a@b.c" })).toBe(false);
    expect((await db.doc("users/u1").get()).data()).toMatchObject({ plan: "premium", minuteCount: 4, displayName: "Renamed" });
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()).toMatchObject({ used: 1, rewardBonus: 2 });
  });

  it("missing auth fields are stored as null, not undefined", async () => {
    await provisionUser(deps, { uid: "u2" });
    expect((await db.doc("users/u2").get()).data()).toMatchObject({ email: null, displayName: null, photoUrl: null });
  });
});

describe("wipeUser (onUserDeleted)", () => {
  beforeEach(async () => { await clearFirestore(); await clearStorage(); });

  it("removes every doc under the user, all subcollections, and every file — and nobody else's", async () => {
    await provisionUser(deps, { uid: "u1" });
    await provisionUser(deps, { uid: "u2" });
    await db.doc("users/u1/minutes/m1").set({ title: "a", status: "ready", tagIds: [] });
    await db.doc("users/u1/minutes/m1/artifacts/quiz").set({ kind: "quiz" });
    await db.doc("users/u1/minutes/m1/chat/c1").set({ role: "user", text: "hi" });
    await db.doc("users/u1/tags/t1").set({ name: "T" });
    await db.doc("users/u2/minutes/m9").set({ title: "keep", status: "ready", tagIds: [] });
    await bucket.file("users/u1/minutes/m1/source/a.m4a").save("x", { resumable: false });
    await bucket.file("users/u1/minutes/m1/transcript.json").save("{}", { resumable: false });
    await bucket.file("users/u2/minutes/m9/source/b.m4a").save("y", { resumable: false });

    const report = await wipeUser(deps, "u1");
    expect(report).toEqual({ firestoreOk: true, storageOk: true });

    for (const p of ["users/u1", "users/u1/minutes/m1", "users/u1/minutes/m1/artifacts/quiz", "users/u1/minutes/m1/chat/c1", "users/u1/tags/t1", "users/u1/quota/2026-09-23"]) {
      expect((await db.doc(p).get()).exists, p).toBe(false);
    }
    const [u1Files] = await bucket.getFiles({ prefix: "users/u1/" });
    expect(u1Files).toHaveLength(0);

    expect((await db.doc("users/u2/minutes/m9").get()).exists).toBe(true);
    const [u2Files] = await bucket.getFiles({ prefix: "users/u2/" });
    expect(u2Files.map((f) => f.name)).toEqual(["users/u2/minutes/m9/source/b.m4a"]);
  });

  it("is idempotent: wiping a user that no longer exists succeeds", async () => {
    expect(await wipeUser(deps, "ghost")).toEqual({ firestoreOk: true, storageOk: true });
  });

  it("reports a Storage failure without skipping the Firestore half", async () => {
    await provisionUser(deps, { uid: "u1" });
    const broken = { ...deps, bucket: { deleteFiles: async () => { throw new Error("storage down"); } } as unknown as Deps["bucket"] };
    const report = await wipeUser(broken, "u1");
    expect(report).toEqual({ firestoreOk: true, storageOk: false });
    expect((await db.doc("users/u1").get()).exists).toBe(false);
  });
});

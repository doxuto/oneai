/** Runs under `npm run test:integration`. */
import { getStorage } from "firebase-admin/storage";
import { Timestamp } from "firebase-admin/firestore";
import { beforeEach, describe, expect, it } from "vitest";
import { sweep } from "../../src/jobs/sweep.js";
import { expireSources } from "../../src/jobs/retention.js";
import { unitDeps, type Deps } from "../../src/lib/deps.js";
import { clearFirestore, testDb } from "../helpers/emulator.js";

const db = testDb();
const bucket = getStorage().bucket("demo-oneai.appspot.com");
const now = new Date("2026-09-23T03:00:00.000Z");
const deps: Deps = unitDeps({ db, bucket: bucket as Deps["bucket"], now: () => now });
const ago = (h: number) => Timestamp.fromDate(new Date(now.getTime() - h * 3600 * 1000));
const days = (d: number) => ago(d * 24);

describe("sweep", () => {
  beforeEach(async () => { await clearFirestore(); const [files] = await bucket.getFiles({ prefix: "users/" }); await Promise.all(files.map((f) => f.delete())); });

  it("deletes uploads abandoned for more than 24 h, keeps fresh ones", async () => {
    await db.doc("users/u1/minutes/old").set({ status: "uploading", createdAt: ago(30) });
    await bucket.file("users/u1/minutes/old/source/a.m4a").save("x");
    await db.doc("users/u1/minutes/fresh").set({ status: "uploading", createdAt: ago(1) });
    const r = await sweep(deps);
    expect(r.abandonedUploads).toBe(1);
    expect((await db.doc("users/u1/minutes/old").get()).exists).toBe(false);
    expect((await db.doc("users/u1/minutes/fresh").get()).exists).toBe(true);
    expect((await bucket.getFiles({ prefix: "users/u1/minutes/old/" }))[0]).toHaveLength(0);
  });

  it("fails notes stuck in processing for more than 2 h and refunds their credit", async () => {
    await db.doc("users/u1/minutes/stuck").set({ status: "transcribing", statusUpdatedAt: ago(3), createdAt: ago(3) });
    await db.doc("transcriptionJobs/j1").set({ uid: "u1", minuteId: "stuck", state: "running", periodId: "2026-09-23", quotaRefunded: false });
    await db.doc("users/u1/quota/2026-09-23").set({ used: 1, baseLimit: 1, rewardBonus: 0 });
    await db.doc("users/u1/minutes/ok").set({ status: "transcribing", statusUpdatedAt: ago(1), createdAt: ago(1) });
    const r = await sweep(deps);
    expect(r.stuckJobs).toBe(1);
    expect((await db.doc("users/u1/minutes/stuck").get()).data()).toMatchObject({ status: "failed", failure: { code: "stuck" } });
    expect((await db.doc("transcriptionJobs/j1").get()).data()).toMatchObject({ state: "failed", quotaRefunded: true });
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.used).toBe(0);
    expect((await db.doc("users/u1/minutes/ok").get()).data()?.status).toBe("transcribing");
  });

  it("removes Storage prefixes whose note no longer exists", async () => {
    await bucket.file("users/u1/minutes/ghost/source/a.m4a").save("x");
    await bucket.file("users/u1/minutes/ghost/transcript.json").save("{}");
    await db.doc("users/u1/minutes/real").set({ status: "ready", createdAt: ago(1) });
    await bucket.file("users/u1/minutes/real/source/a.m4a").save("x");
    const r = await sweep(deps);
    expect(r.orphanPrefixes).toBe(1);
    expect((await bucket.getFiles({ prefix: "users/u1/minutes/ghost/" }))[0]).toHaveLength(0);
    expect((await bucket.getFiles({ prefix: "users/u1/minutes/real/" }))[0]).toHaveLength(1);
  });

  it("deletes finished jobs older than 7 days", async () => {
    await db.doc("transcriptionJobs/old").set({ uid: "u1", minuteId: "m", state: "done", finishedAt: ago(8 * 24) });
    await db.doc("transcriptionJobs/recent").set({ uid: "u1", minuteId: "m", state: "done", finishedAt: ago(24) });
    await db.doc("transcriptionJobs/live").set({ uid: "u1", minuteId: "m", state: "running" });
    const r = await sweep(deps);
    expect(r.oldJobs).toBe(1);
    expect((await db.doc("transcriptionJobs/old").get()).exists).toBe(false);
    expect((await db.doc("transcriptionJobs/recent").get()).exists).toBe(true);
    expect((await db.doc("transcriptionJobs/live").get()).exists).toBe(true);
  });

  describe("source retention", () => {
    async function readyNote(uid: string, id: string, readyDaysAgo: number, expiresDaysAgo: number | null) {
      const path = `users/${uid}/minutes/${id}/source/a.m4a`;
      await bucket.file(path).save("audio");
      await bucket.file(`users/${uid}/minutes/${id}/transcript.json`).save("{}");
      await db.doc(`users/${uid}/minutes/${id}`).set({
        status: "ready", statusUpdatedAt: days(readyDaysAgo), createdAt: days(readyDaysAgo), sourcePath: path,
        sourceState: "available", sourceExpiresAt: expiresDaysAgo === null ? null : days(expiresDaysAgo),
        transcriptPath: `users/${uid}/minutes/${id}/transcript.json`, summary: { title: "S", text: "t", icon: null, sections: [] },
      });
    }

    it("removes only the source bytes of an expired note; transcript, summary and note stay", async () => {
      await db.doc("users/u1").set({ plan: "free" });
      await readyNote("u1", "old", 10, 3);   // free = 7 days; ready 10 days ago → due
      await readyNote("u1", "fresh", 2, -5); // expires in 5 days
      const r = await sweep(deps);
      expect(r.expiredSources).toBe(1);
      const old = (await db.doc("users/u1/minutes/old").get()).data()!;
      expect(old).toMatchObject({ status: "ready", sourceState: "expired", sourcePath: null });
      expect(old.summary.title).toBe("S");
      expect((await bucket.file("users/u1/minutes/old/source/a.m4a").exists())[0]).toBe(false);
      expect((await bucket.file("users/u1/minutes/old/transcript.json").exists())[0]).toBe(true);
      expect((await db.doc("users/u1/minutes/fresh").get()).data()?.sourceState).toBe("available");
      expect((await bucket.file("users/u1/minutes/fresh/source/a.m4a").exists())[0]).toBe(true);
    });

    it("a user who upgraded keeps audio for the premium window instead of the old date", async () => {
      await db.doc("users/u1").set({ plan: "premium", planExpiresAt: Timestamp.fromDate(new Date(now.getTime() + 30 * 86400000)) });
      await readyNote("u1", "n", 10, 3); // stamped as free (7d) but user is premium now (90d)
      const r = await expireSources(deps, now);
      expect(r).toEqual({ expired: 0, extended: 1 });
      const d = (await db.doc("users/u1/minutes/n").get()).data()!;
      expect(d.sourceState).toBe("available");
      expect(d.sourceExpiresAt.toDate().toISOString()).toBe(new Date(now.getTime() + 80 * 86400000).toISOString()); // ready 10d ago + 90d
    });

    it("retention -1 means never: the stamp is cleared and nothing is deleted", async () => {
      const forever: Deps = { ...deps, limits: { ...deps.limits, premium: { ...deps.limits.premium, sourceRetentionDays: -1 } } };
      await db.doc("users/u1").set({ plan: "premium", planExpiresAt: null });
      await readyNote("u1", "n", 400, 300);
      expect(await expireSources(forever, now)).toEqual({ expired: 0, extended: 1 });
      expect((await db.doc("users/u1/minutes/n").get()).data()?.sourceExpiresAt).toBeNull();
    });

    it("a second run does nothing (expired notes leave the query)", async () => {
      await db.doc("users/u1").set({ plan: "free" });
      await readyNote("u1", "old", 10, 3);
      await expireSources(deps, now);
      expect(await expireSources(deps, now)).toEqual({ expired: 0, extended: 0 });
    });
  });

  it("is a no-op on a clean project", async () => {
    expect(await sweep(deps)).toEqual({ abandonedUploads: 0, stuckJobs: 0, orphanPrefixes: 0, oldJobs: 0, expiredSources: 0 });
  });
});

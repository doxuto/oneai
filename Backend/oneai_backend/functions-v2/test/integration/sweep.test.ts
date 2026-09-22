/** Runs under `npm run test:integration`. */
import { getStorage } from "firebase-admin/storage";
import { Timestamp } from "firebase-admin/firestore";
import { beforeEach, describe, expect, it } from "vitest";
import { sweep } from "../../src/jobs/sweep.js";
import { unitDeps, type Deps } from "../../src/lib/deps.js";
import { clearFirestore, testDb } from "../helpers/emulator.js";

const db = testDb();
const bucket = getStorage().bucket("demo-oneai.appspot.com");
const now = new Date("2026-09-23T03:00:00.000Z");
const deps: Deps = unitDeps({ db, bucket: bucket as Deps["bucket"], now: () => now });
const ago = (h: number) => Timestamp.fromDate(new Date(now.getTime() - h * 3600 * 1000));

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

  it("is a no-op on a clean project", async () => {
    expect(await sweep(deps)).toEqual({ abandonedUploads: 0, stuckJobs: 0, orphanPrefixes: 0, oldJobs: 0 });
  });
});

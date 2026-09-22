/** Runs under `npm run test:integration`. */
import { Timestamp } from "firebase-admin/firestore";
import { beforeEach, describe, expect, it } from "vitest";
import { unitDeps } from "../../src/lib/deps.js";
import { recountAfterMinuteWrite } from "../../src/minutes/recount.js";
import { createTagHandler, deleteTagHandler, listTagsHandler, updateTagHandler } from "../../src/tags/handler.js";
import { clearFirestore, fixedNow, testDb } from "../helpers/emulator.js";

const db = testDb();
const deps = unitDeps({ db, now: fixedNow() });
const client = { appVersion: "2.0.0", build: 1, platform: "ios" as const };
const u1 = { uid: "u1", signInProvider: "google.com" };

describe("tags CRUD", () => {
  beforeEach(() => clearFirestore());

  it("create → list → update → delete round trip", async () => {
    const { tag } = await createTagHandler(u1, { client, name: "  Work " }, deps);
    expect(tag).toMatchObject({ name: "Work", minuteCount: 0 });

    const list = await listTagsHandler(u1, { client }, deps);
    expect(list.items.map((t) => t.id)).toEqual([tag.id]);

    const upd = await updateTagHandler(u1, { client, tagId: tag.id, name: "Work stuff" }, deps);
    expect(upd.tag.name).toBe("Work stuff");

    const del = await deleteTagHandler(u1, { client, tagId: tag.id }, deps);
    expect(del.affectedMinuteCount).toBe(0);
    expect((await listTagsHandler(u1, { client }, deps)).items).toEqual([]);
  });

  it("a duplicate name (case/space-insensitive) is already-exists", async () => {
    await createTagHandler(u1, { client, name: "Team Sync" }, deps);
    await expect(createTagHandler(u1, { client, name: " team   SYNC" }, deps)).rejects.toMatchObject({
      code: "already-exists",
      details: { field: "name" },
    });
  });

  it("concurrent creates of the same name yield exactly one tag", async () => {
    const results = await Promise.allSettled(
      Array.from({ length: 5 }, () => createTagHandler(u1, { client, name: "Race" }, deps)),
    );
    const ok = results.filter((r) => r.status === "fulfilled");
    expect(ok).toHaveLength(1);
    expect((await listTagsHandler(u1, { client }, deps)).items).toHaveLength(1);
  });

  it("renaming to another tag's name is already-exists; renaming to itself is fine", async () => {
    const a = await createTagHandler(u1, { client, name: "A" }, deps);
    await createTagHandler(u1, { client, name: "B" }, deps);
    await expect(updateTagHandler(u1, { client, tagId: a.tag.id, name: "b" }, deps)).rejects.toMatchObject({
      code: "already-exists",
    });
    const same = await updateTagHandler(u1, { client, tagId: a.tag.id, name: "a" }, deps);
    expect(same.tag.name).toBe("a");
  });

  it("list is sorted by name, case-insensitively", async () => {
    for (const n of ["zeta", "Alpha", "mid"]) await createTagHandler(u1, { client, name: n }, deps);
    const list = await listTagsHandler(u1, { client }, deps);
    expect(list.items.map((t) => t.name)).toEqual(["Alpha", "mid", "zeta"]);
  });

  it("deleting a tag detaches it from every note and reports the count", async () => {
    const { tag } = await createTagHandler(u1, { client, name: "Gone" }, deps);
    for (let i = 0; i < 3; i++) {
      await db.doc(`users/u1/minutes/m${i}`).set({
        title: `m${i}`,
        status: "ready",
        tagIds: i < 2 ? [tag.id, "other"] : ["other"],
        createdAt: Timestamp.now(),
      });
    }
    const del = await deleteTagHandler(u1, { client, tagId: tag.id }, deps);
    expect(del.affectedMinuteCount).toBe(2);
    for (let i = 0; i < 3; i++) {
      const tags = (await db.doc(`users/u1/minutes/m${i}`).get()).data()?.tagIds as string[];
      expect(tags).not.toContain(tag.id);
      expect(tags).toContain("other");
    }
  });

  it("tags are per user", async () => {
    const { tag } = await createTagHandler(u1, { client, name: "Mine" }, deps);
    const u2 = { uid: "u2", signInProvider: "apple.com" };
    expect((await listTagsHandler(u2, { client }, deps)).items).toEqual([]);
    await expect(deleteTagHandler(u2, { client, tagId: tag.id }, deps)).rejects.toMatchObject({
      code: "not-found",
    });
  });
});

describe("recountAfterMinuteWrite", () => {
  beforeEach(async () => {
    await clearFirestore();
    await db.doc("users/u1").set({ minuteCount: 99 }); // deliberately wrong
    await db.doc("users/u1/tags/t1").set({ name: "T1", nameLower: "t1", minuteCount: 99 });
    await db.doc("users/u1/tags/t2").set({ name: "T2", nameLower: "t2", minuteCount: 99 });
  });

  it("on create: recomputes the user's total from a count() query, not an increment", async () => {
    await db.doc("users/u1/minutes/m1").set({ tagIds: ["t1"], createdAt: Timestamp.now() });
    const touched = await recountAfterMinuteWrite(db, "u1", undefined, { tagIds: ["t1"] });
    expect(touched).toEqual(["t1"]);
    expect((await db.doc("users/u1").get()).data()?.minuteCount).toBe(1);
    expect((await db.doc("users/u1/tags/t1").get()).data()?.minuteCount).toBe(1);
    expect((await db.doc("users/u1/tags/t2").get()).data()?.minuteCount).toBe(99); // untouched
  });

  it("is idempotent: running twice for the same event writes the same numbers", async () => {
    await db.doc("users/u1/minutes/m1").set({ tagIds: ["t1"], createdAt: Timestamp.now() });
    await recountAfterMinuteWrite(db, "u1", undefined, { tagIds: ["t1"] });
    await recountAfterMinuteWrite(db, "u1", undefined, { tagIds: ["t1"] });
    expect((await db.doc("users/u1").get()).data()?.minuteCount).toBe(1);
    expect((await db.doc("users/u1/tags/t1").get()).data()?.minuteCount).toBe(1);
  });

  it("on tag change: only the tags whose membership changed are touched", async () => {
    await db.doc("users/u1/minutes/m1").set({ tagIds: ["t2"], createdAt: Timestamp.now() });
    const touched = await recountAfterMinuteWrite(db, "u1", { tagIds: ["t1"] }, { tagIds: ["t2"] });
    expect(touched.sort()).toEqual(["t1", "t2"]);
    expect((await db.doc("users/u1/tags/t1").get()).data()?.minuteCount).toBe(0);
    expect((await db.doc("users/u1/tags/t2").get()).data()?.minuteCount).toBe(1);
    expect((await db.doc("users/u1").get()).data()?.minuteCount).toBe(99); // no create/delete → untouched
  });

  it("on delete: user total goes down; a tag that no longer exists is skipped", async () => {
    await recountAfterMinuteWrite(db, "u1", { tagIds: ["t1", "ghost"] }, undefined);
    expect((await db.doc("users/u1").get()).data()?.minuteCount).toBe(0);
    expect((await db.doc("users/u1/tags/ghost").get()).exists).toBe(false);
  });
});

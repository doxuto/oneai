import { getStorage } from "firebase-admin/storage";
import { beforeEach, describe, expect, it } from "vitest";
import { deleteGlossaryTermHandler, glossaryTermsFor, listGlossaryHandler, upsertGlossaryTermHandler } from "../../src/glossary/handler.js";
import { unitDeps, type Deps } from "../../src/lib/deps.js";
import { clearFirestore, fixedNow, testDb } from "../helpers/emulator.js";

const db = testDb();
const bucket = getStorage().bucket("demo-oneai.appspot.com");
const deps: Deps = unitDeps({ db, bucket: bucket as Deps["bucket"], now: fixedNow() });
const client = { appVersion: "2.0.0", build: 1, platform: "ios" as const };
const u1 = { uid: "u1", signInProvider: "google.com" };

describe("glossary (S11-10)", () => {
  beforeEach(() => clearFirestore());

  it("upsert creates, re-upsert with a different casing updates the same entry, list is oldest first, delete removes", async () => {
    const a = await upsertGlossaryTermHandler(u1, { client, term: "VinFast", hint: "the company" }, deps);
    expect(a.term).toMatchObject({ term: "VinFast", hint: "the company" });
    const b = await upsertGlossaryTermHandler(u1, { client, term: "vinfast" }, deps);
    expect(b.term.id).toBe(a.term.id);
    expect(b.term.term).toBe("vinfast");
    expect(b.term.hint).toBe("the company"); // merge keeps the hint
    await upsertGlossaryTermHandler(u1, { client, term: "Ana" }, deps);
    const { items } = await listGlossaryHandler(u1, { client }, deps);
    expect(items.map((t) => t.term)).toEqual(["vinfast", "Ana"]);
    expect(await glossaryTermsFor(db, "u1")).toEqual(["vinfast (the company)", "Ana"]);
    await deleteGlossaryTermHandler(u1, { client, termId: a.term.id }, deps);
    expect((await listGlossaryHandler(u1, { client }, deps)).items.map((t) => t.term)).toEqual(["Ana"]);
    await deleteGlossaryTermHandler(u1, { client, termId: "missing-id" }, deps); // no-op
  });

  it("is per user", async () => {
    await upsertGlossaryTermHandler(u1, { client, term: "secret" }, deps);
    expect((await listGlossaryHandler({ uid: "u2", signInProvider: "google.com" }, { client }, deps)).items).toEqual([]);
  });
});

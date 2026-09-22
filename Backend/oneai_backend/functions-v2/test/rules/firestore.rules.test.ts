/**
 * Rules tests use the modular WEB SDK through the rules-unit-testing
 * environment — never the Admin SDK, which bypasses rules.
 * Runs under `npm run test:integration`.
 */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
  type RulesTestEnvironment,
} from "@firebase/rules-unit-testing";
import { collection, doc, getDoc, getDocs, setDoc, deleteDoc, updateDoc } from "firebase/firestore";
import { afterAll, beforeAll, beforeEach, describe, it } from "vitest";

let env: RulesTestEnvironment;

beforeAll(async () => {
  const [host, port] = (process.env.FIRESTORE_EMULATOR_HOST ?? "127.0.0.1:8080").split(":");
  env = await initializeTestEnvironment({
    projectId: "demo-oneai",
    firestore: {
      host,
      port: Number(port),
      rules: readFileSync(fileURLToPath(new URL("../../../firestore.rules", import.meta.url)), "utf8"),
    },
  });
});
afterAll(() => env.cleanup());

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, "users/u1"), { plan: "free" });
    await setDoc(doc(db, "users/u1/minutes/m1"), { title: "mine", status: "ready" });
    await setDoc(doc(db, "users/u1/minutes/m1/chat/c1"), { role: "user", text: "hi" });
    await setDoc(doc(db, "users/u1/minutes/m1/artifacts/speakers"), { kind: "speakers" });
    await setDoc(doc(db, "users/u1/tags/t1"), { name: "Work" });
    await setDoc(doc(db, "users/u1/quota/2026-09-23"), { used: 0 });
    await setDoc(doc(db, "adRewards/tx1"), { uid: "u1", amount: 1 });
    await setDoc(doc(db, "transcriptionJobs/j1"), { uid: "u1" });
  });
});

const owner = () => env.authenticatedContext("u1").firestore();
const other = () => env.authenticatedContext("u2").firestore();
const anon = () => env.unauthenticatedContext().firestore();

describe("users/{uid}", () => {
  it("owner can get", () => assertSucceeds(getDoc(doc(owner(), "users/u1"))));
  it("other user cannot get", () => assertFails(getDoc(doc(other(), "users/u1"))));
  it("unauthenticated cannot get", () => assertFails(getDoc(doc(anon(), "users/u1"))));
  it("nobody can list users", () => assertFails(getDocs(collection(owner(), "users"))));
  it("owner cannot write (callables only)", () =>
    assertFails(updateDoc(doc(owner(), "users/u1"), { plan: "premium" })));
});

describe("users/{uid}/minutes", () => {
  it("owner can get and list", async () => {
    await assertSucceeds(getDoc(doc(owner(), "users/u1/minutes/m1")));
    await assertSucceeds(getDocs(collection(owner(), "users/u1/minutes")));
  });
  it("other user cannot get or list", async () => {
    await assertFails(getDoc(doc(other(), "users/u1/minutes/m1")));
    await assertFails(getDocs(collection(other(), "users/u1/minutes")));
  });
  it("unauthenticated cannot read", () => assertFails(getDoc(doc(anon(), "users/u1/minutes/m1"))));
  it("owner cannot create, update or delete", async () => {
    await assertFails(setDoc(doc(owner(), "users/u1/minutes/m2"), { title: "x" }));
    await assertFails(updateDoc(doc(owner(), "users/u1/minutes/m1"), { title: "y" }));
    await assertFails(deleteDoc(doc(owner(), "users/u1/minutes/m1")));
  });
  it("subcollections (chat, artifacts) follow the same rule", async () => {
    await assertSucceeds(getDocs(collection(owner(), "users/u1/minutes/m1/chat")));
    await assertSucceeds(getDoc(doc(owner(), "users/u1/minutes/m1/artifacts/speakers")));
    await assertFails(getDocs(collection(other(), "users/u1/minutes/m1/chat")));
    await assertFails(setDoc(doc(owner(), "users/u1/minutes/m1/chat/c2"), { text: "x" }));
  });
});

describe("users/{uid}/tags and quota", () => {
  it("owner reads tags, other cannot, nobody writes", async () => {
    await assertSucceeds(getDocs(collection(owner(), "users/u1/tags")));
    await assertFails(getDocs(collection(other(), "users/u1/tags")));
    await assertFails(setDoc(doc(owner(), "users/u1/tags/t2"), { name: "x" }));
  });
  it("owner can get a quota doc but not list or write", async () => {
    await assertSucceeds(getDoc(doc(owner(), "users/u1/quota/2026-09-23")));
    await assertFails(getDocs(collection(owner(), "users/u1/quota")));
    await assertFails(updateDoc(doc(owner(), "users/u1/quota/2026-09-23"), { used: 0 }));
  });
});

describe("server-only collections", () => {
  it("adRewards is unreadable and unwritable even by the uid it names", async () => {
    await assertFails(getDoc(doc(owner(), "adRewards/tx1")));
    await assertFails(setDoc(doc(owner(), "adRewards/tx2"), { uid: "u1", amount: 999 }));
  });
  it("transcriptionJobs likewise", async () => {
    await assertFails(getDoc(doc(owner(), "transcriptionJobs/j1")));
  });
  it("an unknown top-level collection is closed", async () => {
    await assertFails(getDoc(doc(owner(), "whatever/x")));
    await assertFails(setDoc(doc(owner(), "whatever/x"), { a: 1 }));
  });
});

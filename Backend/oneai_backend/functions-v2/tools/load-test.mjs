#!/usr/bin/env node
/**
 * Load test for the transcription path against the emulator (S10-02).
 * Exercises the two places where concurrency bites — the quota transaction
 * in startTranscription and the job state machine in runPipeline — with the
 * vendors replaced by fakes, so it measures OUR code, not ElevenLabs.
 *
 *   npm run build
 *   firebase emulators:exec --only firestore,storage --project demo-oneai "node tools/load-test.mjs"
 *
 * Env: USERS (default 100), CONTENTION (parallel starts by ONE user, default 50),
 *      QUOTA (that user's daily limit, default 5), STT_MS (fake vendor latency, default 150).
 */
import { performance } from "node:perf_hooks";
import { randomUUID } from "node:crypto";
import { getApps, initializeApp } from "firebase-admin/app";
import { Timestamp, getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { unitDeps } from "../lib/lib/deps.js";
import { startTranscriptionHandler } from "../lib/transcribe/handler.js";
import { runPipeline } from "../lib/transcribe/pipeline.js";

for (const v of ["FIRESTORE_EMULATOR_HOST", "FIREBASE_STORAGE_EMULATOR_HOST"]) {
  if (!process.env[v]) process.env[v] = { FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080", FIREBASE_STORAGE_EMULATOR_HOST: "127.0.0.1:9199" }[v];
}
if (getApps().length === 0) initializeApp({ projectId: "demo-oneai", storageBucket: "demo-oneai.appspot.com" });
const db = getFirestore();
const bucket = getStorage().bucket();

const USERS = Number(process.env.USERS ?? 100);
const CONTENTION = Number(process.env.CONTENTION ?? 50);
const QUOTA = Number(process.env.QUOTA ?? 5);
const STT_MS = Number(process.env.STT_MS ?? 150);
const client = { appVersion: "2.0.0", build: 1, platform: "ios" };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const transcript = { durationSeconds: 60, languageCode: "eng", languageProbability: 0.9, text: "hello world ".repeat(50).trim(),
  segments: [{ startSeconds: 0, endSeconds: 60, text: "hello world", speakerId: "speaker_0", speakerLabel: "Speaker 1" }] };
const summary = { contentKind: "other", title: "Load", text: "t", iconEmoji: "📝", sections: [{ title: "Overview", bullets: ["• t"] }], calendarEvents: [] };

let sttCalls = 0, llmCalls = 0;
const deps = unitDeps({
  db, bucket, now: () => new Date(),
  limits: {
    free: { dailyLimit: QUOTA, maxDurationSeconds: 1800, aiCallsPerDay: 30, maxActiveJobs: 1 },
    premium: { dailyLimit: 1000, maxDurationSeconds: 14400, aiCallsPerDay: 300, maxActiveJobs: 100 },
  },
  services: {
    enqueue: async () => {},
    stt: { vendor: "fake", model: "fake", transcribe: async () => { sttCalls++; await sleep(STT_MS + Math.random() * STT_MS); return { transcript, vendor: "fake", model: "fake" }; } },
    llmHeavy: { vendor: "openai", streamText: async () => { throw new Error("unused"); }, generateJson: async () => { llmCalls++; await sleep(50); return { data: summary, model: "fake", tokens: { input: 1, output: 1 } }; } },
    audioDurationSeconds: async () => 60,
    pdfText: async () => "",
    push: { send: async (ms) => ms.map((m) => ({ token: m.token, ok: true, unregistered: false })) },
  },
});

async function seedUser(uid, plan, n) {
  await db.doc(`users/${uid}`).set({ plan, planExpiresAt: null, createdAt: Timestamp.now() });
  const ids = [];
  for (let i = 0; i < n; i++) {
    const id = `m${i}`;
    const path = `users/${uid}/minutes/${id}/source/a.m4a`;
    await bucket.file(path).save("audio-bytes", { resumable: false });
    await db.doc(`users/${uid}/minutes/${id}`).set({ title: id, status: "uploading", sourceType: "audio", sourcePath: path, sourceContentType: "audio/x-m4a", sourceSizeBytes: 11, tagIds: [], createdAt: Timestamp.now(), updatedAt: Timestamp.now() });
    ids.push(id);
  }
  return ids;
}
const pct = (arr, p) => { const s = [...arr].sort((a, b) => a - b); return s[Math.min(s.length - 1, Math.floor(p * s.length))]; };
const startInput = (minuteId) => ({ client, minuteId, requestId: randomUUID(), summaryLanguage: "en", timezone: "Asia/Ho_Chi_Minh" });

console.log(`\n== 1. contention: ONE free user, ${CONTENTION} parallel starts, quota ${QUOTA}`);
{
  const ids = await seedUser("hot", "free", CONTENTION);
  const t0 = performance.now();
  const results = await Promise.allSettled(ids.map((id) => startTranscriptionHandler({ uid: "hot", signInProvider: "x" }, startInput(id), deps)));
  const ok = results.filter((r) => r.status === "fulfilled").length;
  const codes = {};
  for (const r of results) if (r.status === "rejected") codes[r.reason?.code ?? "?"] = (codes[r.reason?.code ?? "?"] ?? 0) + 1;
  const quota = (await db.collection("users/hot/quota").get()).docs[0]?.data();
  // maxActiveJobs for free is 1, so at most 1 gets through here; the quota field must agree.
  console.log(`   accepted=${ok} refused=${JSON.stringify(codes)} quota.used=${quota?.used} in ${(performance.now() - t0).toFixed(0)}ms`);
  if (ok !== quota?.used) { console.error("   ✗ quota.used does not match accepted starts — transaction leak"); process.exitCode = 1; }
  else console.log("   ✓ charged exactly once per accepted start");
}

console.log(`\n== 2. throughput: ${USERS} premium users, 1 job each, start + pipeline in parallel`);
{
  const uids = Array.from({ length: USERS }, (_, i) => `u${i}`);
  await Promise.all(uids.map((u) => seedUser(u, "premium", 1)));
  const t0 = performance.now();
  const startLat = [];
  const jobs = await Promise.all(uids.map(async (u) => {
    const s = performance.now();
    const req = startInput("m0");
    await startTranscriptionHandler({ uid: u, signInProvider: "x" }, req, deps);
    startLat.push(performance.now() - s);
    return { uid: u, minuteId: "m0", jobId: req.requestId };
  }));
  const t1 = performance.now();
  const runLat = [];
  const outcomes = await Promise.all(jobs.map(async (j) => {
    const s = performance.now();
    const o = await runPipeline(j, deps, { attempt: 0, maxAttempts: 3 });
    runLat.push(performance.now() - s);
    return o;
  }));
  const t2 = performance.now();
  const done = outcomes.filter((o) => o === "done").length;
  const ready = (await db.collectionGroup("minutes").where("status", "==", "ready").get()).size;
  console.log(`   starts: ${USERS} in ${(t1 - t0).toFixed(0)}ms (p50 ${pct(startLat, 0.5).toFixed(0)}ms, p95 ${pct(startLat, 0.95).toFixed(0)}ms)`);
  console.log(`   pipelines: ${done}/${USERS} done in ${(t2 - t1).toFixed(0)}ms (p50 ${pct(runLat, 0.5).toFixed(0)}ms, p95 ${pct(runLat, 0.95).toFixed(0)}ms); stt=${sttCalls} llm=${llmCalls}`);
  console.log(`   notes ready: ${ready}`);
  if (done !== USERS || sttCalls !== USERS + 0 || llmCalls !== USERS) { console.error("   ✗ every job must call each vendor exactly once"); process.exitCode = 1; }
  else console.log("   ✓ one STT + one LLM call per job, no duplicates, no losses");
}

console.log(`\n== 3. redelivery: every job run a second time`);
{
  const snap = await db.collection("transcriptionJobs").where("state", "==", "done").limit(USERS).get();
  const before = sttCalls;
  const again = await Promise.all(snap.docs.map((d) => runPipeline({ uid: d.data().uid, minuteId: d.data().minuteId, jobId: d.id }, deps, { attempt: 1, maxAttempts: 3 })));
  const skipped = again.filter((o) => o === "skipped").length;
  console.log(`   skipped=${skipped}/${snap.size}, extra vendor calls=${sttCalls - before}`);
  if (skipped !== snap.size || sttCalls !== before) { console.error("   ✗ redelivery must be a no-op"); process.exitCode = 1; }
  else console.log("   ✓ at-least-once delivery is safe");
}
console.log(process.exitCode ? "\nFAILED" : "\nOK");

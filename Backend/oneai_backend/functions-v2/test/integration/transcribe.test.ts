/** Runs under `npm run test:integration`. Full flow with fake STT/LLM against the emulator. */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { getStorage } from "firebase-admin/storage";
import { Timestamp } from "firebase-admin/firestore";
import { beforeEach, describe, expect, it } from "vitest";
import { SummarizeOutput } from "../../src/ai/summarize.js";
import { unitDeps, type Deps } from "../../src/lib/deps.js";
import { convertScribe } from "../../src/lib/stt/convert.js";
import type { ElevenLabsResponse, SttResult } from "../../src/lib/stt/types.js";
import { HttpsError } from "firebase-functions/v2/https";
import { cancelTranscriptionHandler, startTranscriptionHandler } from "../../src/transcribe/handler.js";
import { runPipeline } from "../../src/transcribe/pipeline.js";
import { reapStaleJobs } from "../../src/jobs/reap.js";
import type { PushMessage } from "../../src/lib/push/types.js";
import { registerDeviceHandler } from "../../src/push/handler.js";
import { clearFirestore, fixedNow, testDb } from "../helpers/emulator.js";

const db = testDb();
const bucket = getStorage().bucket("demo-oneai.appspot.com");
const scribe = JSON.parse(readFileSync(fileURLToPath(new URL("../fixtures/scribe-small.json", import.meta.url)), "utf8")) as ElevenLabsResponse;
const asResult = (r: ElevenLabsResponse): SttResult => ({ transcript: convertScribe(r), vendor: "fake", model: "fake-1" });
const client = { appVersion: "2.0.0", build: 1, platform: "ios" as const };
const u1 = { uid: "u1", signInProvider: "google.com" };
const REQ = "3f2f1b9e-7a4a-4c1e-9d3a-2b7f0c9a1d11";
const startInput = { client, minuteId: "m1", requestId: REQ, summaryLanguage: "vi", timezone: "Asia/Ho_Chi_Minh" };

const goodSummary = SummarizeOutput.parse({
  contentKind: "team_meeting", title: "Standup", text: "We synced.", iconEmoji: "📝",
  sections: [{ title: "Overview", bullets: ["• We synced."] }],
  calendarEvents: [{ id: "e1", title: "Review", description: "d", datetime: "2026-09-24T10:00:00+07:00", participants: [], rawText: "review tomorrow at 10" }],
});

function makeDeps(over: { enqueued?: unknown[]; stt?: () => Promise<SttResult>; llm?: () => Promise<unknown>; duration?: number | null; failEnqueue?: boolean; pushed?: PushMessage[] } = {}): Deps {
  const enqueued = over.enqueued ?? [];
  return unitDeps({
    db, bucket: bucket as Deps["bucket"], now: fixedNow(),
    services: {
      enqueue: async (_q, p) => { if (over.failEnqueue) throw new Error("queue down"); enqueued.push(p); },
      stt: { vendor: "fake", model: "fake", transcribe: over.stt ?? (async () => asResult(scribe)) },
      llmHeavy: { vendor: "openai", streamText: async () => { throw new Error("unused"); }, generateJson: async () => ({ data: (await (over.llm ?? (async () => goodSummary))()) as never, model: "fake", tokens: { input: 1, output: 1 } }) },
      audioDurationSeconds: async () => over.duration === undefined ? 3.9 : over.duration,
      pdfText: async (b) => Buffer.from(b).toString("utf8"),
      concatAudio: async (parts) => Buffer.concat(parts.map((p) => Buffer.from(p))),
      push: { send: async (ms) => { over.pushed?.push(...ms); return ms.map((m) => ({ token: m.token, ok: true, unregistered: false })); } },
    },
  });
}

async function seed(opts: { plan?: "free" | "premium"; status?: string; sourceType?: "audio" | "pdf"; content?: string } = {}) {
  await db.doc("users/u1").set({ plan: opts.plan ?? "free", planExpiresAt: null });
  const path = `users/u1/minutes/m1/source/${opts.sourceType === "pdf" ? "a.pdf" : "a.m4a"}`;
  const body = opts.content ?? "audio-bytes";
  await bucket.file(path).save(body, { resumable: false });
  await db.doc("users/u1/minutes/m1").set({
    title: "a", status: opts.status ?? "uploading", sourceType: opts.sourceType ?? "audio",
    sourcePath: path, sourceContentType: opts.sourceType === "pdf" ? "application/pdf" : "audio/x-m4a", sourceSizeBytes: Buffer.byteLength(body),
    tagIds: [], createdAt: Timestamp.now(), updatedAt: Timestamp.now(),
  });
}

describe("startTranscription", () => {
  beforeEach(async () => { await clearFirestore(); const [files] = await bucket.getFiles({ prefix: "users/" }); await Promise.all(files.map((f) => f.delete())); });

  it("charges quota, marks queued, creates the job and enqueues exactly once", async () => {
    await seed();
    const enqueued: unknown[] = [];
    const out = await startTranscriptionHandler(u1, startInput, makeDeps({ enqueued }));
    expect(out).toEqual({ minuteId: "m1", status: "queued", duplicate: false });
    expect(enqueued).toEqual([{ uid: "u1", minuteId: "m1", jobId: REQ }]);
    expect((await db.doc("users/u1/minutes/m1").get()).data()).toMatchObject({ status: "queued", summaryLanguage: "vi" });
    expect((await db.doc(`transcriptionJobs/${REQ}`).get()).data()).toMatchObject({ state: "queued", periodId: "2026-09-23", quotaRefunded: false });
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.usedSeconds).toBe(60);
  });

  it("the same requestId twice is a no-op with duplicate:true and no second charge", async () => {
    await seed();
    const enqueued: unknown[] = [];
    const deps = makeDeps({ enqueued });
    await startTranscriptionHandler(u1, startInput, deps);
    const again = await startTranscriptionHandler(u1, startInput, deps);
    expect(again.duplicate).toBe(true);
    expect(enqueued).toHaveLength(1);
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.usedSeconds).toBe(60);
  });

  it("a second note today on the free plan is resource-exhausted and nothing is written", async () => {
    await seed();
    await startTranscriptionHandler(u1, startInput, makeDeps());
    await db.doc("users/u1/minutes/m2").set({ title: "b", status: "uploading", sourceType: "audio", sourcePath: "users/u1/minutes/m1/source/a.m4a", sourceSizeBytes: 10, tagIds: [], createdAt: Timestamp.now() });
    await expect(
      startTranscriptionHandler(u1, { ...startInput, minuteId: "m2", requestId: "9f2f1b9e-7a4a-4c1e-9d3a-2b7f0c9a1d22" }, makeDeps()),
    ).rejects.toMatchObject({ code: "resource-exhausted", details: { resetAt: "2026-09-23T17:00:00.000Z" } });
    expect((await db.doc("users/u1/minutes/m2").get()).data()?.status).toBe("uploading");
  });

  it("refuses when the upload never landed", async () => {
    await seed();
    await bucket.file("users/u1/minutes/m1/source/a.m4a").delete();
    await expect(startTranscriptionHandler(u1, startInput, makeDeps())).rejects.toMatchObject({ code: "failed-precondition", details: { reason: "noSource" } });
  });

  it("refuses when the note is already processing", async () => {
    await seed({ status: "transcribing" });
    await expect(startTranscriptionHandler(u1, startInput, makeDeps())).rejects.toMatchObject({ code: "failed-precondition", details: { reason: "alreadyProcessing" } });
  });

  it("pre-checks the declared duration against the free cap", async () => {
    await seed();
    await expect(startTranscriptionHandler(u1, { ...startInput, durationSeconds: 601 }, makeDeps())).rejects.toMatchObject({ code: "failed-precondition", details: { reason: "durationLimit", limitSeconds: 600 } });
  });

  it("if the queue is down, the charge is undone and the note is failed, not stuck in queued", async () => {
    await seed();
    await expect(startTranscriptionHandler(u1, startInput, makeDeps({ failEnqueue: true }))).rejects.toMatchObject({ code: "unavailable" });
    expect((await db.doc("users/u1/minutes/m1").get()).data()?.status).toBe("failed");
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.usedSeconds).toBe(0);
    expect((await db.doc(`transcriptionJobs/${REQ}`).get()).data()).toMatchObject({ state: "failed", quotaRefunded: true });
  });
});

describe("runPipeline", () => {
  beforeEach(async () => { await clearFirestore(); const [files] = await bucket.getFiles({ prefix: "users/" }); await Promise.all(files.map((f) => f.delete())); });

  async function started(deps: Deps) {
    await startTranscriptionHandler(u1, startInput, deps);
    return { uid: "u1", minuteId: "m1", jobId: REQ };
  }

  it("audio: queued → ready with summary, transcript in Storage, preview, duration, calendar artifact", async () => {
    await seed();
    const deps = makeDeps();
    const out = await runPipeline(await started(deps), deps, { attempt: 0, maxAttempts: 3 });
    expect(out).toBe("done");

    const m = (await db.doc("users/u1/minutes/m1").get()).data()!;
    expect(m).toMatchObject({ status: "ready", title: "Standup", iconEmoji: "📝", contentKind: "team_meeting", durationSeconds: 3.9, languageCode: "eng", transcriptPath: "users/u1/minutes/m1/transcript.json", stt: { vendor: "fake", model: "fake-1" } });
    expect(m.transcriptPreview).toContain("Hello everyone");
    expect(m.sourceState).toBe("available");
    expect(m.sourceExpiresAt.toDate().toISOString()).toBe("2026-09-30T03:00:00.000Z"); // free plan: 7 days after ready
    expect(m.summary.sections[0].bullets).toEqual(["• We synced."]);

    const [buf] = await bucket.file("users/u1/minutes/m1/transcript.json").download();
    expect(JSON.parse(buf.toString()).segments).toHaveLength(2);

    expect((await db.doc("users/u1/minutes/m1/artifacts/calendarEvents").get()).data()?.data.events[0].id).toBe("e1");
    expect((await db.doc(`transcriptionJobs/${REQ}`).get()).data()).toMatchObject({ state: "done", attempt: 1 });
  });

  it("pdf: text goes straight to the summariser as one document segment", async () => {
    await seed({ sourceType: "pdf", content: "This is the PDF text." });
    const deps = makeDeps();
    await runPipeline(await started(deps), deps, { attempt: 0, maxAttempts: 3 });
    const m = (await db.doc("users/u1/minutes/m1").get()).data()!;
    expect(m.status).toBe("ready");
    expect(m.durationSeconds).toBeNull();
    const [buf] = await bucket.file("users/u1/minutes/m1/transcript.json").download();
    expect(JSON.parse(buf.toString()).segments[0].speakerId).toBe("document");
  });

  it("measured duration over the free cap: failed with durationLimit, quota refunded, vendor never called", async () => {
    await seed();
    let sttCalls = 0;
    const deps = makeDeps({ duration: 601, stt: async () => { sttCalls++; return asResult(scribe); } });
    const out = await runPipeline(await started(deps), deps, { attempt: 0, maxAttempts: 3 });
    expect(out).toBe("failed");
    expect(sttCalls).toBe(0);
    const m = (await db.doc("users/u1/minutes/m1").get()).data()!;
    expect(m.status).toBe("failed");
    expect(m.failure.code).toBe("failed-precondition");
    expect(m.failure.message).toMatch(/longer than your plan/);
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.usedSeconds).toBe(0);
  });

  it("premium is not capped at 10 minutes", async () => {
    await seed({ plan: "premium" });
    const deps = makeDeps({ duration: 5400 });
    expect(await runPipeline(await started(deps), deps, { attempt: 0, maxAttempts: 3 })).toBe("done");
  });

  it("quota is reserved from the declared length and settled to the measured one (refund of the excess)", async () => {
    await seed();
    const deps = makeDeps({ duration: 130 });
    await startTranscriptionHandler(u1, { ...startInput, durationSeconds: 300 }, deps);
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.usedSeconds).toBe(300);
    expect(await runPipeline({ uid: "u1", minuteId: "m1", jobId: REQ }, deps, { attempt: 0, maxAttempts: 3 })).toBe("done");
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.usedSeconds).toBe(130);
    expect((await db.doc(`transcriptionJobs/${REQ}`).get()).data()?.chargedSeconds).toBe(130);
  });

  it("a free file longer than what is left today fails with reason quota before STT and refunds the reservation", async () => {
    await seed();
    await db.doc("users/u1/quota/2026-09-23").set({ periodId: "2026-09-23", usedSeconds: 500, limitSeconds: 600 });
    let sttCalls = 0;
    const deps = makeDeps({ duration: 400, stt: async () => { sttCalls++; return asResult(scribe); } });
    await startTranscriptionHandler(u1, { ...startInput, durationSeconds: 60 }, deps); // 560 ≤ 600: reserved
    expect(await runPipeline({ uid: "u1", minuteId: "m1", jobId: REQ }, deps, { attempt: 0, maxAttempts: 3 })).toBe("failed");
    expect(sttCalls).toBe(0);
    const m = (await db.doc("users/u1/minutes/m1").get()).data()!;
    expect(m.failure.message).toMatch(/free minutes/);
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.usedSeconds).toBe(500);
  });

  it("start refuses outright when the declared length does not fit today's remaining minutes", async () => {
    await seed();
    await db.doc("users/u1/quota/2026-09-23").set({ periodId: "2026-09-23", usedSeconds: 500, limitSeconds: 600 });
    await expect(startTranscriptionHandler(u1, { ...startInput, durationSeconds: 200 }, makeDeps())).rejects.toMatchObject({
      code: "resource-exhausted", details: { reason: "quota", remainingSeconds: 100, requestedSeconds: 200 },
    });
    expect((await db.doc("users/u1/minutes/m1").get()).data()?.status).toBe("uploading");
  });

  it("glossary terms ride along with the keywords into the job and the STT request (S11-10)", async () => {
    await seed();
    await db.doc("users/u1/glossary/g1").set({ term: "VinFast", hint: "company", createdAt: new Date("2026-09-01T00:00:00Z") });
    let seenTerms: string[] | undefined;
    const deps = makeDeps({ stt: async () => asResult(scribe) });
    const spy: Deps = { ...deps, services: { ...deps.services, stt: { ...deps.services.stt, transcribe: async (req) => { seenTerms = req.keyterms; return asResult(scribe); } } } };
    await startTranscriptionHandler(u1, { ...startInput, keywords: ["OKR"] }, spy);
    expect((await db.doc(`transcriptionJobs/${REQ}`).get()).data()?.options.keyterms).toEqual(["OKR", "VinFast (company)"]);
    expect(await runPipeline({ uid: "u1", minuteId: "m1", jobId: REQ }, spy, { attempt: 0, maxAttempts: 3 })).toBe("done");
    expect(seenTerms).toEqual(["OKR", "VinFast (company)"]);
  });

  it("a PDF is a flat charge (pdfChargeSeconds) and is not settled", async () => {
    await seed({ sourceType: "pdf", content: "%PDF-1.4 text" });
    const deps = makeDeps();
    await startTranscriptionHandler(u1, startInput, deps);
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.usedSeconds).toBe(300);
  });

  it("a retryable STT error rethrows for Cloud Tasks and keeps the credit while attempts remain", async () => {
    await seed();
    const deps = makeDeps({ stt: async () => { throw new HttpsError("unavailable", "down"); } });
    const payload = await started(deps);
    await expect(runPipeline(payload, deps, { attempt: 0, maxAttempts: 3 })).rejects.toMatchObject({ code: "unavailable" });
    expect((await db.doc("users/u1/minutes/m1").get()).data()?.status).toBe("transcribing");
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.usedSeconds).toBe(60);
    expect((await db.doc(`transcriptionJobs/${REQ}`).get()).data()).toMatchObject({ state: "running", error: { code: "unavailable" } });
  });

  it("the same error on the last attempt fails the note and refunds", async () => {
    await seed();
    const deps = makeDeps({ stt: async () => { throw new HttpsError("unavailable", "down"); } });
    const payload = await started(deps);
    expect(await runPipeline(payload, deps, { attempt: 2, maxAttempts: 3 })).toBe("failed");
    expect((await db.doc("users/u1/minutes/m1").get()).data()?.status).toBe("failed");
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.usedSeconds).toBe(0);
  });

  it("an LLM schema failure is never cached: note fails, no summary written", async () => {
    await seed();
    const deps = makeDeps({ llm: async () => { throw new HttpsError("unavailable", "bad shape"); } });
    const payload = await started(deps);
    expect(await runPipeline(payload, deps, { attempt: 2, maxAttempts: 3 })).toBe("failed");
    const m = (await db.doc("users/u1/minutes/m1").get()).data()!;
    expect(m.summary ?? null).toBeNull();
    expect(m.transcriptPath).toBe("users/u1/minutes/m1/transcript.json"); // STT work is kept for a retry
  });

  it("a finished job is not re-run on redelivery", async () => {
    await seed();
    const deps = makeDeps();
    const payload = await started(deps);
    await runPipeline(payload, deps, { attempt: 0, maxAttempts: 3 });
    expect(await runPipeline(payload, deps, { attempt: 1, maxAttempts: 3 })).toBe("skipped");
  });

  it("cancel while queued refunds and the worker then skips quietly", async () => {
    await seed();
    const deps = makeDeps();
    const payload = await started(deps);
    await cancelTranscriptionHandler(u1, { client, minuteId: "m1" }, deps);
    expect((await db.doc("users/u1/minutes/m1").get()).data()?.status).toBe("cancelled");
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.usedSeconds).toBe(0);
    expect((await db.doc(`transcriptionJobs/${REQ}`).get()).data()).toMatchObject({ state: "cancelled", quotaRefunded: true });
    expect(await runPipeline(payload, deps, { attempt: 0, maxAttempts: 3 })).toBe("skipped");
  });

  it("cancel mid-flight: the worker stops at the next check-point without writing ready", async () => {
    await seed();
    const deps = makeDeps({ stt: async () => { await cancelTranscriptionHandler(u1, { client, minuteId: "m1" }, deps); return asResult(scribe); } });
    const payload = await started(deps);
    expect(await runPipeline(payload, deps, { attempt: 0, maxAttempts: 3 })).toBe("skipped");
    expect((await db.doc("users/u1/minutes/m1").get()).data()?.status).toBe("cancelled");
  });

  it("cancel when nothing is running is failed-precondition", async () => {
    await seed({ status: "ready" });
    await expect(cancelTranscriptionHandler(u1, { client, minuteId: "m1" }, makeDeps())).rejects.toMatchObject({ code: "failed-precondition", details: { reason: "notProcessing" } });
  });
});

describe("push on completion", () => {
  beforeEach(async () => { await clearFirestore(); const [files] = await bucket.getFiles({ prefix: "users/" }); await Promise.all(files.map((f) => f.delete())); });
  const TOKEN = "fcm-token-".padEnd(60, "a");

  it("ready → one minuteReady push per device, carrying the note id and its new title", async () => {
    await seed();
    const pushed: PushMessage[] = [];
    const deps = makeDeps({ pushed });
    await registerDeviceHandler(u1, { client, token: TOKEN, locale: "vi" }, deps);
    await runPipeline(await started(deps), deps, { attempt: 0, maxAttempts: 3 });
    expect(pushed).toHaveLength(1);
    expect(pushed[0]).toMatchObject({ token: TOKEN, title: "Ghi chú đã sẵn sàng", data: { type: "minuteReady", minuteId: "m1" } });
    expect(pushed[0]?.body).toContain("Standup");
  });

  it("permanent failure → minuteFailed push; a retryable attempt sends nothing", async () => {
    await seed();
    const pushed: PushMessage[] = [];
    const deps = makeDeps({ pushed, stt: async () => { throw new HttpsError("unavailable", "down"); } });
    await registerDeviceHandler(u1, { client, token: TOKEN }, deps);
    const ids = await started(deps);
    await expect(runPipeline(ids, deps, { attempt: 0, maxAttempts: 3 })).rejects.toBeDefined();
    expect(pushed).toHaveLength(0);
    await runPipeline(ids, deps, { attempt: 2, maxAttempts: 3 });
    expect(pushed).toHaveLength(1);
    expect(pushed[0]?.data).toEqual({ type: "minuteFailed", minuteId: "m1" });
  });

  it("no device registered → the pipeline still completes", async () => {
    await seed();
    const pushed: PushMessage[] = [];
    const deps = makeDeps({ pushed });
    expect(await runPipeline(await started(deps), deps, { attempt: 0, maxAttempts: 3 })).toBe("done");
    expect(pushed).toHaveLength(0);
  });

  async function started(deps: Deps) {
    await startTranscriptionHandler(u1, startInput, deps);
    return { uid: "u1", minuteId: "m1", jobId: REQ };
  }
});

describe("job management", () => {
  beforeEach(async () => { await clearFirestore(); const [files] = await bucket.getFiles({ prefix: "users/" }); await Promise.all(files.map((f) => f.delete())); });

  async function seedSecond(id: string) {
    const path = `users/u1/minutes/${id}/source/a.m4a`;
    await bucket.file(path).save("audio-bytes", { resumable: false });
    await db.doc(`users/u1/minutes/${id}`).set({ title: id, status: "uploading", sourceType: "audio", sourcePath: path, sourceContentType: "audio/x-m4a", sourceSizeBytes: 11, tagIds: [], createdAt: Timestamp.now(), updatedAt: Timestamp.now() });
  }

  it("a premium user is capped at maxActiveJobs concurrent jobs; the refused start is not charged", async () => {
    await seed({ plan: "premium" }); // unitDeps premium: maxActiveJobs 2
    await seedSecond("m2");
    await seedSecond("m3");
    const deps = makeDeps();
    await startTranscriptionHandler(u1, startInput, deps);
    await startTranscriptionHandler(u1, { ...startInput, minuteId: "m2", requestId: "3f2f1b9e-7a4a-4c1e-9d3a-2b7f0c9a1d22" }, deps);
    await expect(startTranscriptionHandler(u1, { ...startInput, minuteId: "m3", requestId: "3f2f1b9e-7a4a-4c1e-9d3a-2b7f0c9a1d33" }, deps))
      .rejects.toMatchObject({ code: "resource-exhausted", details: { reason: "tooManyActiveJobs", limit: 2 } });
    expect((await db.doc("users/u1/minutes/m3").get()).data()?.status).toBe("uploading");
    const period = (await db.collection("users/u1/quota").get()).docs[0]?.data();
    expect(period?.usedSeconds).toBe(120);

    // Finishing one frees a slot.
    await runPipeline({ uid: "u1", minuteId: "m1", jobId: REQ }, deps, { attempt: 0, maxAttempts: 3 });
    await expect(startTranscriptionHandler(u1, { ...startInput, minuteId: "m3", requestId: "3f2f1b9e-7a4a-4c1e-9d3a-2b7f0c9a1d33" }, deps)).resolves.toMatchObject({ status: "queued" });
  });

  it("reaper: a job running past the budget is failed, refunded once, the note updated and the user told", async () => {
    await seed();
    const pushed: PushMessage[] = [];
    const deps = makeDeps({ pushed });
    await registerDeviceHandler(u1, { client, token: "fcm-token-".padEnd(60, "a") }, deps);
    await startTranscriptionHandler(u1, startInput, deps);
    const jobRef = db.doc(`transcriptionJobs/${REQ}`);
    await jobRef.update({ state: "running", startedAt: Timestamp.fromMillis(deps.now().getTime() - 45 * 60 * 1000) });
    await db.doc("users/u1/minutes/m1").update({ status: "transcribing" });

    const report = await reapStaleJobs(deps);
    expect(report).toMatchObject({ running: 1, queued: 0, jobIds: [REQ] });
    expect((await jobRef.get()).data()).toMatchObject({ state: "failed", quotaRefunded: true, error: { code: "stale" } });
    expect((await db.doc("users/u1/minutes/m1").get()).data()).toMatchObject({ status: "failed", failure: { code: "stale" } });
    const quota = (await db.collection("users/u1/quota").get()).docs[0]?.data();
    expect(quota?.usedSeconds).toBe(0);
    expect(pushed).toHaveLength(1);
    expect(pushed[0]?.data.type).toBe("minuteFailed");

    // Second pass: nothing left, and no double refund.
    expect(await reapStaleJobs(deps)).toMatchObject({ running: 0, queued: 0 });
    expect((await db.collection("users/u1/quota").get()).docs[0]?.data().usedSeconds).toBe(0);
  });

  it("reaper: a queued job nobody ever picked up is failed as lost; fresh jobs are left alone", async () => {
    await seed();
    await seedSecond("m2");
    const deps = makeDeps();
    await startTranscriptionHandler(u1, { ...startInput, minuteId: "m2", requestId: "3f2f1b9e-7a4a-4c1e-9d3a-2b7f0c9a1d22" }, deps);
    await db.doc("transcriptionJobs/3f2f1b9e-7a4a-4c1e-9d3a-2b7f0c9a1d22").update({ createdAt: Timestamp.fromMillis(deps.now().getTime() - 2 * 60 * 60 * 1000) });
    await db.doc("users/u1").update({ plan: "premium" });
    await startTranscriptionHandler(u1, startInput, deps); // fresh, must survive

    const report = await reapStaleJobs(deps);
    expect(report).toMatchObject({ running: 0, queued: 1 });
    expect((await db.doc("transcriptionJobs/3f2f1b9e-7a4a-4c1e-9d3a-2b7f0c9a1d22").get()).data()?.error?.code).toBe("lost");
    expect((await db.doc(`transcriptionJobs/${REQ}`).get()).data()?.state).toBe("queued");
  });

  it("the done job records which STT vendor/model produced the transcript", async () => {
    await seed();
    const deps = makeDeps();
    await startTranscriptionHandler(u1, startInput, deps);
    await runPipeline({ uid: "u1", minuteId: "m1", jobId: REQ }, deps, { attempt: 0, maxAttempts: 3 });
    expect((await db.doc(`transcriptionJobs/${REQ}`).get()).data()).toMatchObject({ state: "done", stt: { vendor: "fake", model: "fake-1" } });
  });

  it("S11-09 chunked recording: partCount checks every part, the worker joins them into sourcePath and deletes the parts", async () => {
    await db.doc("users/u1").set({ plan: "free", planExpiresAt: null });
    await db.doc("users/u1/minutes/m1").set({ title: "a", status: "uploading", sourceType: "audio", sourcePath: "users/u1/minutes/m1/source/a.m4a", sourceContentType: "audio/x-m4a", sourceSizeBytes: 6, tagIds: [], createdAt: Timestamp.now(), updatedAt: Timestamp.now() });
    await bucket.file("users/u1/minutes/m1/source/parts/part-000.m4a").save("abc", { resumable: false });
    const deps = makeDeps();
    await expect(startTranscriptionHandler(u1, { ...startInput, partCount: 2 }, deps)).rejects.toMatchObject({ code: "failed-precondition", details: { reason: "noSource", missingPart: 1 } });
    await bucket.file("users/u1/minutes/m1/source/parts/part-001.m4a").save("def", { resumable: false });
    await startTranscriptionHandler(u1, { ...startInput, partCount: 2 }, deps);
    expect((await db.doc("users/u1/minutes/m1").get()).data()?.sourceParts).toBe(2);
    const seen: string[] = [];
    const d2 = makeDeps({ stt: async () => { return asResult(scribe); } });
    const sttSpy = d2.services.stt.transcribe;
    d2.services.stt.transcribe = async (req, signal) => { seen.push(Buffer.from(req.audio).toString("utf8")); return sttSpy(req, signal); };
    await runPipeline({ uid: "u1", minuteId: "m1", jobId: REQ }, d2, { attempt: 0, maxAttempts: 3 });
    expect(seen).toEqual(["abcdef"]);
    const [merged] = await bucket.file("users/u1/minutes/m1/source/a.m4a").download();
    expect(merged.toString("utf8")).toBe("abcdef");
    expect((await bucket.file("users/u1/minutes/m1/source/parts/part-000.m4a").exists())[0]).toBe(false);
    const m = (await db.doc("users/u1/minutes/m1").get()).data();
    expect(m?.status).toBe("ready");
    expect(m?.sourceParts).toBeNull();
    expect(m?.sourceSizeBytes).toBe(6);
  });
});


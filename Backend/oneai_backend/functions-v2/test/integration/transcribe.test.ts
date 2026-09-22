/** Runs under `npm run test:integration`. Full flow with fake STT/LLM against the emulator. */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { getStorage } from "firebase-admin/storage";
import { Timestamp } from "firebase-admin/firestore";
import { beforeEach, describe, expect, it } from "vitest";
import { SummarizeOutput } from "../../src/ai/summarize.js";
import { unitDeps, type Deps } from "../../src/lib/deps.js";
import type { ElevenLabsResponse } from "../../src/lib/stt/types.js";
import { HttpsError } from "firebase-functions/v2/https";
import { cancelTranscriptionHandler, startTranscriptionHandler } from "../../src/transcribe/handler.js";
import { runPipeline } from "../../src/transcribe/pipeline.js";
import { clearFirestore, fixedNow, testDb } from "../helpers/emulator.js";

const db = testDb();
const bucket = getStorage().bucket("demo-oneai.appspot.com");
const scribe = JSON.parse(readFileSync(fileURLToPath(new URL("../fixtures/scribe-small.json", import.meta.url)), "utf8")) as ElevenLabsResponse;
const client = { appVersion: "2.0.0", build: 1, platform: "ios" as const };
const u1 = { uid: "u1", signInProvider: "google.com" };
const REQ = "3f2f1b9e-7a4a-4c1e-9d3a-2b7f0c9a1d11";
const startInput = { client, minuteId: "m1", requestId: REQ, summaryLanguage: "vi", timezone: "Asia/Ho_Chi_Minh" };

const goodSummary = SummarizeOutput.parse({
  contentKind: "team_meeting", title: "Standup", text: "We synced.", iconEmoji: "📝",
  sections: [{ title: "Overview", bullets: ["• We synced."] }],
  calendarEvents: [{ id: "e1", title: "Review", description: "d", datetime: "2026-09-24T10:00:00+07:00", participants: [], rawText: "review tomorrow at 10" }],
});

function makeDeps(over: { enqueued?: unknown[]; stt?: () => Promise<ElevenLabsResponse>; llm?: () => Promise<unknown>; duration?: number | null; failEnqueue?: boolean } = {}): Deps {
  const enqueued = over.enqueued ?? [];
  return unitDeps({
    db, bucket: bucket as Deps["bucket"], now: fixedNow(),
    services: {
      enqueue: async (_q, p) => { if (over.failEnqueue) throw new Error("queue down"); enqueued.push(p); },
      stt: { transcribe: over.stt ?? (async () => scribe) },
      llmHeavy: { vendor: "openai", streamText: async () => { throw new Error("unused"); }, generateJson: async () => ({ data: (await (over.llm ?? (async () => goodSummary))()) as never, model: "fake", tokens: { input: 1, output: 1 } }) },
      audioDurationSeconds: async () => over.duration === undefined ? 3.9 : over.duration,
      pdfText: async (b) => Buffer.from(b).toString("utf8"),
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
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.used).toBe(1);
  });

  it("the same requestId twice is a no-op with duplicate:true and no second charge", async () => {
    await seed();
    const enqueued: unknown[] = [];
    const deps = makeDeps({ enqueued });
    await startTranscriptionHandler(u1, startInput, deps);
    const again = await startTranscriptionHandler(u1, startInput, deps);
    expect(again.duplicate).toBe(true);
    expect(enqueued).toHaveLength(1);
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.used).toBe(1);
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
    await expect(startTranscriptionHandler(u1, { ...startInput, durationSeconds: 1801 }, makeDeps())).rejects.toMatchObject({ code: "failed-precondition", details: { reason: "durationLimit", limitSeconds: 1800 } });
  });

  it("if the queue is down, the charge is undone and the note is failed, not stuck in queued", async () => {
    await seed();
    await expect(startTranscriptionHandler(u1, startInput, makeDeps({ failEnqueue: true }))).rejects.toMatchObject({ code: "unavailable" });
    expect((await db.doc("users/u1/minutes/m1").get()).data()?.status).toBe("failed");
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.used).toBe(0);
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
    expect(m).toMatchObject({ status: "ready", title: "Standup", iconEmoji: "📝", contentKind: "team_meeting", durationSeconds: 3.9, languageCode: "eng", transcriptPath: "users/u1/minutes/m1/transcript.json" });
    expect(m.transcriptPreview).toContain("Hello everyone");
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
    const deps = makeDeps({ duration: 1801, stt: async () => { sttCalls++; return scribe; } });
    const out = await runPipeline(await started(deps), deps, { attempt: 0, maxAttempts: 3 });
    expect(out).toBe("failed");
    expect(sttCalls).toBe(0);
    const m = (await db.doc("users/u1/minutes/m1").get()).data()!;
    expect(m.status).toBe("failed");
    expect(m.failure.code).toBe("failed-precondition");
    expect(m.failure.message).toMatch(/longer than your plan/);
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.used).toBe(0);
  });

  it("premium is not capped at 30 minutes", async () => {
    await seed({ plan: "premium" });
    const deps = makeDeps({ duration: 5400 });
    expect(await runPipeline(await started(deps), deps, { attempt: 0, maxAttempts: 3 })).toBe("done");
  });

  it("a retryable STT error rethrows for Cloud Tasks and keeps the credit while attempts remain", async () => {
    await seed();
    const deps = makeDeps({ stt: async () => { throw new HttpsError("unavailable", "down"); } });
    const payload = await started(deps);
    await expect(runPipeline(payload, deps, { attempt: 0, maxAttempts: 3 })).rejects.toMatchObject({ code: "unavailable" });
    expect((await db.doc("users/u1/minutes/m1").get()).data()?.status).toBe("transcribing");
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.used).toBe(1);
    expect((await db.doc(`transcriptionJobs/${REQ}`).get()).data()).toMatchObject({ state: "running", error: { code: "unavailable" } });
  });

  it("the same error on the last attempt fails the note and refunds", async () => {
    await seed();
    const deps = makeDeps({ stt: async () => { throw new HttpsError("unavailable", "down"); } });
    const payload = await started(deps);
    expect(await runPipeline(payload, deps, { attempt: 2, maxAttempts: 3 })).toBe("failed");
    expect((await db.doc("users/u1/minutes/m1").get()).data()?.status).toBe("failed");
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.used).toBe(0);
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
    expect((await db.doc("users/u1/quota/2026-09-23").get()).data()?.used).toBe(0);
    expect((await db.doc(`transcriptionJobs/${REQ}`).get()).data()).toMatchObject({ state: "cancelled", quotaRefunded: true });
    expect(await runPipeline(payload, deps, { attempt: 0, maxAttempts: 3 })).toBe("skipped");
  });

  it("cancel mid-flight: the worker stops at the next check-point without writing ready", async () => {
    await seed();
    const deps = makeDeps({ stt: async () => { await cancelTranscriptionHandler(u1, { client, minuteId: "m1" }, deps); return scribe; } });
    const payload = await started(deps);
    expect(await runPipeline(payload, deps, { attempt: 0, maxAttempts: 3 })).toBe("skipped");
    expect((await db.doc("users/u1/minutes/m1").get()).data()?.status).toBe("cancelled");
  });

  it("cancel when nothing is running is failed-precondition", async () => {
    await seed({ status: "ready" });
    await expect(cancelTranscriptionHandler(u1, { client, minuteId: "m1" }, makeDeps())).rejects.toMatchObject({ code: "failed-precondition", details: { reason: "notProcessing" } });
  });
});

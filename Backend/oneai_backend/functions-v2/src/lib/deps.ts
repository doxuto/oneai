/**
 * Everything a handler needs from the outside world, passed in explicitly so
 * tests can swap the clock, the limits, or point `db` at the emulator, and
 * replace every external service with a fake.
 */
import type { Firestore } from "firebase-admin/firestore";
import { getBucket, getDb, type Bucket } from "./admin.js";
import type { Embedder } from "./llm/embeddings.js";
import type { LlmClient } from "./llm/types.js";
import type { Pusher } from "./push/types.js";
import type { SttClient } from "./stt/types.js";
import {
  ELEVENLABS_API_KEY,
  ELEVENLABS_MODEL,
  EMBEDDING_DIM,
  FREE_AI_CALLS_DAILY,
  FREE_DAILY_SECONDS,
  FREE_MAX_ACTIVE_JOBS,
  FREE_MAX_DURATION_SECONDS,
  FREE_SOURCE_RETENTION_DAYS,
  GEMINI_API_KEY,
  GEMINI_EMBEDDING_MODEL,
  GEMINI_MODEL,
  GEMINI_STT_MODEL,
  LLM_VENDOR,
  MIN_CLIENT_VERSION,
  OPENAI_API_KEY,
  OPENAI_EMBEDDING_MODEL,
  OPENAI_MODEL,
  OPENAI_MODEL_HEAVY,
  PREMIUM_AI_CALLS_DAILY,
  PREMIUM_DAILY_SECONDS,
  PDF_CHARGE_SECONDS,
  PREMIUM_MAX_ACTIVE_JOBS,
  PREMIUM_MAX_DURATION_SECONDS,
  PREMIUM_SOURCE_RETENTION_DAYS,
  STT_FALLBACK_VENDOR,
  STT_VENDOR,
  SHARE_BASE_URL,
} from "./params.js";
export type { Bucket };

export interface PlanLimits {
  /** Seconds of audio per day; 0 = unlimited. */
  dailySeconds: number;
  /** Longest single recording accepted. */
  maxDurationSeconds: number;
  /** Flat charge for a PDF, in seconds. */
  pdfChargeSeconds: number;
  /** Model calls per day (chat + generators + speaker mapping); cache hits are free. */
  aiCallsPerDay: number;
  /** Transcription jobs queued/running at the same time. */
  maxActiveJobs: number;
  /** Days the source file survives after `ready`; -1 = forever. */
  sourceRetentionDays: number;
}

export interface Services {
  stt: SttClient;
  /** Cheap model for chat/quiz/etc. */
  llm: LlmClient;
  /** Stronger model for the one-shot summary at ingest. */
  llmHeavy: LlmClient;
  /** Note / question vectors (S11-01/02). */
  embedder: Embedder;
  enqueue: (queue: string, payload: Record<string, unknown>) => Promise<void>;
  audioDurationSeconds: (bytes: Uint8Array, contentType: string) => Promise<number | null>;
  pdfText: (bytes: Uint8Array) => Promise<string>;
  /** S11-09: joins recording chunks (ffmpeg concat, stream copy). */
  concatAudio: (parts: Uint8Array[], ext: string) => Promise<Uint8Array>;
  /** FCM. */
  push: Pusher;
}

export interface Deps {
  db: Firestore;
  bucket: Bucket;
  now: () => Date;
  minClientVersion: string;
  /** Base URL the share page is served from; tokens are appended as `?t=`. */
  shareBaseUrl: string;
  limits: { free: PlanLimits; premium: PlanLimits };
  services: Services;
}

/**
 * Production deps. Services are built on first access, so a function that
 * never touches STT does not need the ELEVENLABS_API_KEY secret bound.
 */
export function liveDeps(): Deps {
  const lazy = <T>(build: () => T) => {
    let v: T | undefined;
    return () => (v ??= build());
  };
  const stt = lazy(async () => {
    const { makeStt, parseSttVendor, withSttFallback } = await import("./stt/index.js");
    const cfg = {
      elevenlabs: { apiKey: ELEVENLABS_API_KEY.value(), model: ELEVENLABS_MODEL.value() },
      gemini: { apiKey: GEMINI_API_KEY.value(), model: GEMINI_STT_MODEL.value() },
      timeoutMs: 480_000, // < worker timeoutSeconds 540
    };
    const primaryVendor = parseSttVendor(STT_VENDOR.value()) ?? "elevenlabs";
    const fallbackVendor = parseSttVendor(STT_FALLBACK_VENDOR.value());
    const primary = await makeStt(primaryVendor, cfg);
    if (!fallbackVendor || fallbackVendor === primaryVendor) return primary;
    return withSttFallback(primary, await makeStt(fallbackVendor, cfg));
  });
  const vendorOf = async () => (await import("./llm/index.js")).parseVendor(LLM_VENDOR.value());
  const llm = lazy(async () => {
    const { makeLlm } = await import("./llm/index.js");
    const vendor = await vendorOf();
    return vendor === "gemini"
      ? makeLlm("gemini", { apiKey: GEMINI_API_KEY.value(), model: GEMINI_MODEL.value(), timeoutMs: 90_000 })
      : makeLlm("openai", { apiKey: OPENAI_API_KEY.value(), model: OPENAI_MODEL.value(), timeoutMs: 90_000 });
  });
  const llmHeavy = lazy(async () => {
    const { makeLlm } = await import("./llm/index.js");
    const vendor = await vendorOf();
    return vendor === "gemini"
      ? makeLlm("gemini", { apiKey: GEMINI_API_KEY.value(), model: GEMINI_MODEL.value(), timeoutMs: 180_000 })
      : makeLlm("openai", { apiKey: OPENAI_API_KEY.value(), model: OPENAI_MODEL_HEAVY.value(), timeoutMs: 180_000 });
  });

  const embedder = lazy(async () => {
    const { geminiEmbedder, openAiEmbedder } = await import("./llm/embeddings.js");
    const vendor = await vendorOf();
    const dimension = EMBEDDING_DIM.value();
    return vendor === "gemini"
      ? geminiEmbedder({ apiKey: GEMINI_API_KEY.value(), model: GEMINI_EMBEDDING_MODEL.value(), dimension, timeoutMs: 30_000 })
      : openAiEmbedder({ apiKey: OPENAI_API_KEY.value(), model: OPENAI_EMBEDDING_MODEL.value(), dimension, timeoutMs: 30_000 });
  });

  const services: Services = {
    stt: {
      vendor: STT_VENDOR.value(),
      model: "lazy",
      transcribe: async (req, signal) => (await stt()).transcribe(req, signal),
    },
    llm: {
      vendor: "openai",
      generateJson: async (req, signal) => (await llm()).generateJson(req, signal),
      streamText: async (req, onDelta, signal) => (await llm()).streamText(req, onDelta, signal),
    },
    llmHeavy: {
      vendor: "openai",
      generateJson: async (req, signal) => (await llmHeavy()).generateJson(req, signal),
      streamText: async (req, onDelta, signal) => (await llmHeavy()).streamText(req, onDelta, signal),
    },
    embedder: {
      vendor: "openai",
      dimension: EMBEDDING_DIM.value(),
      embed: async (texts, task, signal) => (await embedder()).embed(texts, task, signal),
    },
    enqueue: async (queue, payload) => {
      const { getFunctions } = await import("firebase-admin/functions");
      await getFunctions().taskQueue(queue).enqueue(payload);
    },
    audioDurationSeconds: async (bytes, ct) => (await import("./media/audio.js")).audioDurationSeconds(bytes, ct),
    pdfText: async (bytes) => (await import("./media/pdf.js")).pdfText(bytes),
    concatAudio: async (parts, ext) => (await import("./media/concat.js")).concatAudio(parts, ext),
    push: { send: async (m) => (await import("./push/fcm.js")).fcmPusher().send(m) },
  };

  return {
    db: getDb(),
    bucket: getBucket(),
    now: () => new Date(),
    minClientVersion: MIN_CLIENT_VERSION.value(),
    shareBaseUrl: SHARE_BASE_URL.value() || `https://asia-southeast1-${process.env.GCLOUD_PROJECT ?? "oneai"}.cloudfunctions.net/sharePage`,
    limits: {
      free: { dailySeconds: FREE_DAILY_SECONDS.value(), pdfChargeSeconds: PDF_CHARGE_SECONDS.value(), maxDurationSeconds: FREE_MAX_DURATION_SECONDS.value(), aiCallsPerDay: FREE_AI_CALLS_DAILY.value(), maxActiveJobs: FREE_MAX_ACTIVE_JOBS.value(), sourceRetentionDays: FREE_SOURCE_RETENTION_DAYS.value() },
      premium: { dailySeconds: PREMIUM_DAILY_SECONDS.value(), pdfChargeSeconds: PDF_CHARGE_SECONDS.value(), maxDurationSeconds: PREMIUM_MAX_DURATION_SECONDS.value(), aiCallsPerDay: PREMIUM_AI_CALLS_DAILY.value(), maxActiveJobs: PREMIUM_MAX_ACTIVE_JOBS.value(), sourceRetentionDays: PREMIUM_SOURCE_RETENTION_DAYS.value() },
    },
    services,
  };
}

/**
 * Deps for tests. `db`/`bucket`/services are inert stubs that throw when
 * touched; a test that needs one passes a real emulator db or a fake.
 */
export function unitDeps(overrides: Partial<Deps> & { services?: Partial<Services> } = {}): Deps {
  const explode = (what: string) =>
    new Proxy({}, { get: (_t, k) => { throw new Error(`unitDeps: ${what}.${String(k)} touched`); } });
  const throwing = (name: string) => async () => { throw new Error(`unitDeps: services.${name} touched`); };
  const { services: svc, ...rest } = overrides;
  return {
    db: explode("db") as unknown as Firestore,
    bucket: explode("bucket") as unknown as Bucket,
    now: () => new Date("2026-09-23T03:00:00.000Z"),
    minClientVersion: "2.0.0",
    shareBaseUrl: "https://share.test/s",
    limits: {
      free: { dailySeconds: 600, pdfChargeSeconds: 300, maxDurationSeconds: 600, aiCallsPerDay: 3, maxActiveJobs: 1, sourceRetentionDays: 7 },
      premium: { dailySeconds: 0, pdfChargeSeconds: 300, maxDurationSeconds: 14400, aiCallsPerDay: 300, maxActiveJobs: 2, sourceRetentionDays: 90 },
    },
    ...rest,
    services: {
      stt: { vendor: "fake", model: "fake", transcribe: throwing("stt") },
      push: { send: throwing("push") },
      llm: { vendor: "openai", generateJson: throwing("llm"), streamText: throwing("llm.streamText") },
      embedder: { vendor: "openai", dimension: 4, embed: throwing("embedder") },
      llmHeavy: { vendor: "openai", generateJson: throwing("llmHeavy"), streamText: throwing("llmHeavy.streamText") },
      enqueue: throwing("enqueue"),
      audioDurationSeconds: throwing("audioDurationSeconds"),
      pdfText: throwing("pdfText"),
      concatAudio: throwing("concatAudio"),
      ...svc,
    },
  };
}

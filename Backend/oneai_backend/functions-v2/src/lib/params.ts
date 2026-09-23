/**
 * Params and secrets. functions.config() is removed for new deployments
 * from March 2026 — defineSecret / defineString only.
 */
import { defineInt, defineSecret, defineString } from "firebase-functions/params";

export const ELEVENLABS_API_KEY = defineSecret("ELEVENLABS_API_KEY");
export const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");
export const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
export const REVENUECAT_WEBHOOK_SECRET = defineSecret("REVENUECAT_WEBHOOK_SECRET");

export const LLM_VENDOR = defineString("LLM_VENDOR", { default: "openai" });
export const OPENAI_MODEL = defineString("OPENAI_MODEL", { default: "gpt-4o-mini" });
export const OPENAI_MODEL_HEAVY = defineString("OPENAI_MODEL_HEAVY", { default: "gpt-4o" });
export const GEMINI_MODEL = defineString("GEMINI_MODEL", { default: "gemini-2.0-flash" });
/** S11-01/02 embeddings. Vendor follows LLM_VENDOR; the dimension must match the vector index in firestore.indexes.json. */
export const OPENAI_EMBEDDING_MODEL = defineString("OPENAI_EMBEDDING_MODEL", { default: "text-embedding-3-small" });
export const GEMINI_EMBEDDING_MODEL = defineString("GEMINI_EMBEDDING_MODEL", { default: "gemini-embedding-001" });
export const EMBEDDING_DIM = defineInt("EMBEDDING_DIM", { default: 768 });
export const ELEVENLABS_MODEL = defineString("ELEVENLABS_MODEL", { default: "scribe_v1" });

/** Speech-to-text vendor: "elevenlabs" | "gemini". Fallback runs once when the primary is down; "none" disables it. */
export const STT_VENDOR = defineString("STT_VENDOR", { default: "elevenlabs" });
export const STT_FALLBACK_VENDOR = defineString("STT_FALLBACK_VENDOR", { default: "none" });
export const GEMINI_STT_MODEL = defineString("GEMINI_STT_MODEL", { default: "gemini-2.5-flash" });

export const MIN_CLIENT_VERSION = defineString("MIN_CLIENT_VERSION", { default: "2.0.0" });
/** Public base for read-only share links (S11-05). Empty = the sharePage function's own cloudfunctions.net URL. */
export const SHARE_BASE_URL = defineString("SHARE_BASE_URL", { default: "" });

/** Free plan: seconds of audio per Vietnam day (600 = 10 minutes). Decided 24/09. */
export const FREE_DAILY_SECONDS = defineInt("FREE_DAILY_SECONDS", { default: 600 });
export const FREE_MAX_DURATION_SECONDS = defineInt("FREE_MAX_DURATION_SECONDS", { default: 600 });
/** 0 = unlimited (still counted). */
export const PREMIUM_DAILY_SECONDS = defineInt("PREMIUM_DAILY_SECONDS", { default: 0 });
/** A PDF has no duration; it is charged as this many seconds. */
export const PDF_CHARGE_SECONDS = defineInt("PDF_CHARGE_SECONDS", { default: 300 });
export const PREMIUM_MAX_DURATION_SECONDS = defineInt("PREMIUM_MAX_DURATION_SECONDS", {
  default: 14400,
});
/** Jobs a user may have queued/running at once — keeps one account from monopolising the worker pool. */
export const FREE_MAX_ACTIVE_JOBS = defineInt("FREE_MAX_ACTIVE_JOBS", { default: 1 });
export const PREMIUM_MAX_ACTIVE_JOBS = defineInt("PREMIUM_MAX_ACTIVE_JOBS", { default: 3 });
/**
 * How long the ORIGINAL audio/PDF is kept after a note is ready. The
 * transcript and summary stay forever; only the heavy source bytes expire.
 * 0 = delete as soon as the note is ready; -1 = keep indefinitely.
 */
export const FREE_SOURCE_RETENTION_DAYS = defineInt("FREE_SOURCE_RETENTION_DAYS", { default: 7 });
export const PREMIUM_SOURCE_RETENTION_DAYS = defineInt("PREMIUM_SOURCE_RETENTION_DAYS", { default: 90 });
export const FREE_AI_CALLS_DAILY = defineInt("FREE_AI_CALLS_DAILY", { default: 30 });
export const PREMIUM_AI_CALLS_DAILY = defineInt("PREMIUM_AI_CALLS_DAILY", { default: 300 });

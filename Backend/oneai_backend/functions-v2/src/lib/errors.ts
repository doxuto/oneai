/**
 * HttpsError is the only error type a callable may let escape.
 * firebase-functions-pro/errors-and-logging.
 */
import { HttpsError, type FunctionsErrorCode } from "firebase-functions/v2/https";
import { log } from "./logging.js";

/** gRPC status code -> HttpsError. */
const GRPC_MAP: Record<number, FunctionsErrorCode> = {
  4: "deadline-exceeded",
  5: "not-found",
  6: "already-exists",
  7: "permission-denied",
  8: "resource-exhausted",
  9: "failed-precondition",
  10: "aborted",
  14: "unavailable",
};

function grpcCodeOf(err: unknown): number | undefined {
  if (typeof err === "object" && err !== null && "code" in err) {
    const c = (err as { code: unknown }).code;
    if (typeof c === "number") return c;
  }
  return undefined;
}

/** Map a Firestore/gRPC error onto the HttpsError vocabulary. */
export function mapFirestoreError(err: unknown, ctx: LogFieldsCtx = {}): HttpsError {
  const code = grpcCodeOf(err);
  const mapped = code === undefined ? undefined : GRPC_MAP[code];
  if (mapped === undefined) {
    log.error("firestore.unmapped", { ...ctx, code: code ?? null, error: String(err) });
    return new HttpsError("internal", "Something went wrong");
  }
  return new HttpsError(mapped, "Storage operation failed");
}

type LogFieldsCtx = Record<string, string | number | boolean | null | undefined>;

/**
 * Map an upstream provider (ElevenLabs, OpenAI, Gemini) failure.
 * 429 -> resource-exhausted, 5xx/network -> unavailable, 4xx we caused -> internal.
 */
export function mapProviderError(
  provider: string,
  status: number | undefined,
  err: unknown,
  ctx: LogFieldsCtx = {},
): HttpsError {
  if (status === 429) {
    return new HttpsError("resource-exhausted", "Service is busy, try again shortly", {
      retryAfterSeconds: 30,
    });
  }
  if (status !== undefined && status >= 500) {
    log.warn(`${provider}.upstream_5xx`, { ...ctx, status });
    return new HttpsError("unavailable", "Service temporarily unavailable");
  }
  if (status === undefined) {
    log.warn(`${provider}.network`, { ...ctx, error: String(err) });
    return new HttpsError("unavailable", "Service temporarily unavailable");
  }
  // A 4xx means we built a bad request. Never explain it to the client.
  log.error(`${provider}.bad_request`, { ...ctx, status, error: String(err) });
  return new HttpsError("internal", "Something went wrong");
}

/** Re-throw an HttpsError untouched; wrap anything else as `internal`. */
export function rethrow(err: unknown, event: string, ctx: LogFieldsCtx = {}): never {
  if (err instanceof HttpsError) throw err;
  log.error(event, { ...ctx, error: String(err) });
  throw new HttpsError("internal", "Something went wrong");
}

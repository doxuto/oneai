import { HttpsError } from "firebase-functions/v2/https";
import type { ZodType, ZodTypeDef } from "zod";
import type { ClientInfo } from "../types/common.js";

/** Compare dotted numeric versions. Returns <0, 0, >0. */
export function compareVersions(a: string, b: string): number {
  const pa = a.split(".").map((n) => Number.parseInt(n, 10) || 0);
  const pb = b.split(".").map((n) => Number.parseInt(n, 10) || 0);
  const len = Math.max(pa.length, pb.length);
  for (let i = 0; i < len; i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d !== 0) return d;
  }
  return 0;
}

export function requireMinVersion(client: ClientInfo, minVersion: string): void {
  if (compareVersions(client.appVersion, minVersion) < 0) {
    throw new HttpsError("failed-precondition", "Please update the app to continue", {
      minVersion,
    });
  }
}

/**
 * The only way `raw` becomes typed. Second line of every handler, right after
 * requireCaller(). `minVersion` comes from deps so handlers stay pure.
 */
export function parse<T extends { client: ClientInfo }>(
  // Output/Input split matters: with `.default()` the input type is wider than
  // the output, and `ZodType<T>` alone would collapse them to the wider one.
  schema: ZodType<T, ZodTypeDef, unknown>,
  raw: unknown,
  minVersion: string,
): T {
  const result = schema.safeParse(raw);
  if (!result.success) {
    throw new HttpsError("invalid-argument", "Invalid input", {
      issues: result.error.issues.map((i) => ({
        path: i.path.join("."),
        message: i.message,
      })),
    });
  }
  requireMinVersion(result.data.client, minVersion);
  return result.data;
}

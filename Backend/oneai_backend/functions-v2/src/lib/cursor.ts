import { HttpsError } from "firebase-functions/v2/https";

/**
 * Opaque pagination cursor. envelope-and-naming: the client never inspects it,
 * the server validates it and throws invalid-argument on failure.
 * Forbidden alternatives: page numbers, hasMore next to nextCursor, lastId.
 */
export function encodeCursor(parts: readonly (string | number)[]): string {
  return Buffer.from(JSON.stringify(parts), "utf8").toString("base64url");
}

export function decodeCursor(cursor: string): (string | number)[] {
  try {
    const parsed: unknown = JSON.parse(Buffer.from(cursor, "base64url").toString("utf8"));
    if (!Array.isArray(parsed)) throw new Error("not an array");
    for (const p of parsed) {
      if (typeof p !== "string" && typeof p !== "number") throw new Error("bad element");
    }
    return parsed as (string | number)[];
  } catch {
    throw new HttpsError("invalid-argument", "Invalid cursor");
  }
}

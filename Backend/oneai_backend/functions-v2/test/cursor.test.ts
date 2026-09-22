import { describe, expect, it } from "vitest";
import { decodeCursor, encodeCursor } from "../src/lib/cursor.js";

describe("cursor", () => {
  it("round-trips a [millis, id] pair", () => {
    const c = encodeCursor([1790000000000, "abc123"]);
    expect(decodeCursor(c)).toEqual([1790000000000, "abc123"]);
  });

  it("produces a url-safe string", () => {
    const c = encodeCursor(["a/b+c", 1]);
    expect(c).not.toMatch(/[+/=]/);
  });

  it("rejects garbage", () => {
    expect(() => decodeCursor("not-base64!!")).toThrow();
  });

  it("rejects a non-array payload", () => {
    expect(() => decodeCursor(Buffer.from('{"a":1}').toString("base64url"))).toThrow();
  });

  it("rejects an array with an object element", () => {
    expect(() => decodeCursor(Buffer.from('[{"a":1}]').toString("base64url"))).toThrow();
  });
});

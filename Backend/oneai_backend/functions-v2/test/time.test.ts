import { describe, expect, it } from "vitest";
import { nextPeriodStart, periodIdFor } from "../src/lib/time.js";

describe("periodIdFor", () => {
  it("uses the Vietnam calendar day, not UTC", () => {
    // 2026-09-22T18:00Z is already 2026-09-23 01:00 in Asia/Ho_Chi_Minh.
    expect(periodIdFor(new Date("2026-09-22T18:00:00Z"))).toBe("2026-09-23");
    expect(periodIdFor(new Date("2026-09-22T16:00:00Z"))).toBe("2026-09-22");
  });

  it("formats as yyyy-MM-dd", () => {
    expect(periodIdFor(new Date("2026-01-05T03:00:00Z"))).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });
});

describe("nextPeriodStart", () => {
  it("lands in the following period", () => {
    const now = new Date("2026-09-22T10:00:00Z");
    const next = nextPeriodStart(now);
    expect(next.getTime()).toBeGreaterThan(now.getTime());
    expect(periodIdFor(next)).not.toBe(periodIdFor(now));
  });
});

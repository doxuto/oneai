import { describe, expect, it } from "vitest";
import { compareVersions } from "../src/lib/validate.js";

describe("compareVersions", () => {
  it("orders by major, minor, patch", () => {
    expect(compareVersions("2.0.0", "2.0.0")).toBe(0);
    expect(compareVersions("2.0.1", "2.0.0")).toBeGreaterThan(0);
    expect(compareVersions("1.9.9", "2.0.0")).toBeLessThan(0);
    expect(compareVersions("2.10.0", "2.9.0")).toBeGreaterThan(0);
  });

  it("treats a missing segment as zero", () => {
    expect(compareVersions("2", "2.0.0")).toBe(0);
    expect(compareVersions("2.1", "2.0.9")).toBeGreaterThan(0);
  });

  it("does not crash on non-numeric segments", () => {
    expect(compareVersions("2.0.0-beta", "2.0.0")).toBe(0);
  });
});

import { describe, expect, it } from "vitest";
import { canConsume } from "../../src/quota/quota.js";

describe("canConsume", () => {
  it("free: blocked at the ceiling", () => {
    expect(canConsume({ used: 0, limit: 1 }, "free")).toBe(true);
    expect(canConsume({ used: 1, limit: 1 }, "free")).toBe(false);
  });
  it("free: a reward raises the ceiling rather than lowering usage — 3/5 + 2 ⇒ 3/7", () => {
    expect(canConsume({ used: 3, limit: 5 }, "free")).toBe(true);
    expect(canConsume({ used: 5, limit: 5 }, "free")).toBe(false);
    expect(canConsume({ used: 5, limit: 7 }, "free")).toBe(true);
  });
  it("premium: never blocked, whatever the numbers", () => {
    expect(canConsume({ used: 999, limit: 1 }, "premium")).toBe(true);
  });
});

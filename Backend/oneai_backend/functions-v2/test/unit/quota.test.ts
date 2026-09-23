import { describe, expect, it } from "vitest";
import { canConsume, remainingSeconds } from "../../src/quota/quota.js";

describe("canConsume (seconds)", () => {
  it("free: blocked when the request would cross the ceiling, allowed when it exactly fills it", () => {
    expect(canConsume({ usedSeconds: 0, limitSeconds: 600 }, "free", 600)).toBe(true);
    expect(canConsume({ usedSeconds: 0, limitSeconds: 600 }, "free", 601)).toBe(false);
    expect(canConsume({ usedSeconds: 540, limitSeconds: 600 }, "free", 60)).toBe(true);
    expect(canConsume({ usedSeconds: 541, limitSeconds: 600 }, "free", 60)).toBe(false);
  });
  it("premium, or a 0 limit, is never blocked", () => {
    expect(canConsume({ usedSeconds: 99999, limitSeconds: 600 }, "premium", 1)).toBe(true);
    expect(canConsume({ usedSeconds: 99999, limitSeconds: 0 }, "free", 1)).toBe(true);
  });
  it("remainingSeconds floors at 0 and is infinite for a 0 limit", () => {
    expect(remainingSeconds({ usedSeconds: 500, limitSeconds: 600 })).toBe(100);
    expect(remainingSeconds({ usedSeconds: 700, limitSeconds: 600 })).toBe(0);
    expect(remainingSeconds({ usedSeconds: 700, limitSeconds: 0 })).toBe(Number.POSITIVE_INFINITY);
  });
});

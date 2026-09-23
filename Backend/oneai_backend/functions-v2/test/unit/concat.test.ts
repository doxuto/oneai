import { describe, expect, it } from "vitest";
import { concatAudio, concatListFor, ffmpegBinary } from "../../src/lib/media/concat.js";

describe("chunk concat (S11-09)", () => {
  it("writes the concat-demuxer list with ffmpeg's quote escaping", () => {
    expect(concatListFor(["/tmp/a.m4a", "/tmp/it's.m4a"])).toBe("file '/tmp/a.m4a'\nfile '/tmp/it'\\''s.m4a'\n");
  });
  it("one part is returned as-is, zero parts is an error, a binary path is always resolved", async () => {
    const one = new Uint8Array([1, 2, 3]);
    expect(await concatAudio([one])).toBe(one);
    await expect(concatAudio([])).rejects.toThrow(/no parts/);
    expect(typeof ffmpegBinary()).toBe("string");
  });
});

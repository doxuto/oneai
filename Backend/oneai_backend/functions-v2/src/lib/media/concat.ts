/**
 * S11-09 — joins the chunks of a chunked recording into one file before STT.
 * Chunks come from the same recorder config (AAC-LC m4a), so ffmpeg's concat
 * demuxer with stream copy is exact and fast: no re-encode, no quality loss.
 *
 * The binary comes from `ffmpeg-static` (downloaded at `npm install`; the
 * agent's shell could not fetch it, so it is resolved at runtime and a missing
 * binary falls back to `ffmpeg` on PATH).
 */
import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import { log } from "../logging.js";

const execFileAsync = promisify(execFile);

/** concat-demuxer list: one `file '<path>'` per line, single quotes escaped the ffmpeg way. */
export function concatListFor(paths: string[]): string {
  return paths.map((p) => `file '${p.replace(/'/g, "'\\''")}'`).join("\n") + "\n";
}

export function ffmpegBinary(): string {
  try {
    const bin = createRequire(import.meta.url)("ffmpeg-static") as string | null;
    if (bin) return bin;
  } catch {
    // not installed — fall through
  }
  return "ffmpeg";
}

/** Concatenates `parts` (bytes, in order) into one file of the same container. Returns the merged bytes. */
export async function concatAudio(parts: Uint8Array[], ext = "m4a"): Promise<Uint8Array> {
  if (parts.length === 0) throw new Error("concatAudio: no parts");
  if (parts.length === 1) return parts[0]!;
  const dir = await mkdtemp(join(tmpdir(), "oneai-concat-"));
  try {
    const files: string[] = [];
    for (let i = 0; i < parts.length; i++) {
      const p = join(dir, `part-${String(i).padStart(3, "0")}.${ext}`);
      await writeFile(p, parts[i]!);
      files.push(p);
    }
    const list = join(dir, "list.txt");
    await writeFile(list, concatListFor(files));
    const out = join(dir, `merged.${ext}`);
    const t0 = Date.now();
    await execFileAsync(ffmpegBinary(), ["-hide_banner", "-loglevel", "error", "-y", "-f", "concat", "-safe", "0", "-i", list, "-c", "copy", "-movflags", "+faststart", out], { maxBuffer: 1024 * 1024 });
    const merged = await readFile(out);
    log.info("media.concat", { parts: parts.length, bytes: merged.length, ms: Date.now() - t0 });
    return new Uint8Array(merged);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
}

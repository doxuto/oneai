import { parseBuffer } from "music-metadata";
import { log } from "../logging.js";

/**
 * Duration from bytes. Returns null when unknown — the CALLER decides what
 * that means. v1 returned 0 on failure, which silently defeated the
 * free-plan cap (0 > 1800 is false).
 */
export async function audioDurationSeconds(bytes: Uint8Array, contentType: string): Promise<number | null> {
  try {
    const meta = await parseBuffer(bytes, { mimeType: contentType }, { duration: true });
    const d = meta.format.duration;
    return typeof d === "number" && Number.isFinite(d) && d > 0 ? d : null;
  } catch (err) {
    log.warn("audio.duration_unknown", { contentType, error: String(err) });
    return null;
  }
}

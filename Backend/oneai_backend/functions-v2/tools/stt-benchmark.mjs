#!/usr/bin/env node
/**
 * S11-13 — Vietnamese STT benchmark: runs every file in a folder through
 * ElevenLabs Scribe and Gemini, compares against a reference transcript, and
 * prints WER / CER / latency per vendor so STT_VENDOR is chosen on data.
 *
 *   npm run build
 *   ELEVENLABS_API_KEY=… GEMINI_API_KEY=… node tools/stt-benchmark.mjs ./bench
 *
 * Folder layout: `<name>.m4a|mp3|wav|…` next to `<name>.txt` (the reference,
 * a human transcript). Files without a .txt are transcribed and timed only.
 * Env: VENDORS (default "elevenlabs,gemini"), LANG (ISO-639-3, default "vie";
 * "auto" for detection), ELEVENLABS_MODEL, GEMINI_STT_MODEL, KEYTERMS
 * (comma-separated, e.g. product names), OUT (json report path).
 */
import { readdir, readFile, writeFile } from "node:fs/promises";
import { extname, join, basename } from "node:path";
import { performance } from "node:perf_hooks";
import { makeStt } from "../lib/lib/stt/index.js";
import { errorRates } from "../lib/lib/stt/wer.js";

const dir = process.argv[2];
if (!dir) { console.error("usage: node tools/stt-benchmark.mjs <folder>"); process.exit(2); }
const vendors = (process.env.VENDORS ?? "elevenlabs,gemini").split(",").map((v) => v.trim()).filter(Boolean);
const lang = process.env.LANG_CODE ?? "vie";
const keyterms = (process.env.KEYTERMS ?? "").split(",").map((k) => k.trim()).filter(Boolean);
const AUDIO = new Set([".m4a", ".mp3", ".wav", ".aac", ".ogg", ".flac", ".mp4", ".webm"]);
const MIME = { ".m4a": "audio/mp4", ".mp3": "audio/mpeg", ".wav": "audio/wav", ".aac": "audio/aac", ".ogg": "audio/ogg", ".flac": "audio/flac", ".mp4": "video/mp4", ".webm": "audio/webm" };

const cfg = {
  elevenlabs: { apiKey: process.env.ELEVENLABS_API_KEY ?? "", model: process.env.ELEVENLABS_MODEL ?? "scribe_v1" },
  gemini: { apiKey: process.env.GEMINI_API_KEY ?? "", model: process.env.GEMINI_STT_MODEL ?? "gemini-2.5-flash" },
  timeoutMs: 8 * 60_000,
};
for (const v of vendors) if (!cfg[v]?.apiKey) { console.error(`missing API key for ${v}`); process.exit(2); }

const files = (await readdir(dir)).filter((f) => AUDIO.has(extname(f).toLowerCase())).sort();
if (files.length === 0) { console.error(`no audio files in ${dir}`); process.exit(2); }

const rows = [];
for (const v of vendors) {
  const stt = await makeStt(v, cfg);
  for (const f of files) {
    const ext = extname(f).toLowerCase();
    const audio = await readFile(join(dir, f));
    const refPath = join(dir, `${basename(f, ext)}.txt`);
    const reference = await readFile(refPath, "utf8").catch(() => null);
    const t0 = performance.now();
    try {
      const r = await stt.transcribe({ audio, contentType: MIME[ext] ?? "application/octet-stream", fileName: f, languageCode: lang === "auto" ? undefined : lang, keyterms });
      const ms = Math.round(performance.now() - t0);
      const rates = reference === null ? null : errorRates(reference, r.transcript.text);
      rows.push({ vendor: v, model: r.model, file: f, ms, audioSeconds: r.transcript.durationSeconds, language: r.transcript.languageCode, speakers: new Set(r.transcript.segments.map((s) => s.speakerId)).size, ...rates, hypothesis: r.transcript.text });
      console.log(`${v.padEnd(10)} ${f.padEnd(32)} ${String(ms).padStart(6)} ms  ${rates ? `WER ${(rates.wer * 100).toFixed(1).padStart(5)}%  CER ${(rates.cer * 100).toFixed(1).padStart(5)}%` : "(no reference)"}`);
    } catch (err) {
      rows.push({ vendor: v, file: f, error: String(err?.message ?? err) });
      console.log(`${v.padEnd(10)} ${f.padEnd(32)} FAILED ${String(err?.message ?? err).slice(0, 80)}`);
    }
  }
}

console.log("\nSummary (files with a reference):");
for (const v of vendors) {
  const ok = rows.filter((r) => r.vendor === v && typeof r.wer === "number");
  if (ok.length === 0) { console.log(`  ${v}: no scored files`); continue; }
  const avg = (k) => ok.reduce((s, r) => s + r[k], 0) / ok.length;
  const totalRef = ok.reduce((s, r) => s + r.refWords, 0);
  const wWer = ok.reduce((s, r) => s + r.wer * r.refWords, 0) / totalRef; // weighted by length
  console.log(`  ${v.padEnd(10)} WER ${(wWer * 100).toFixed(1)}% (weighted)  mean CER ${(avg("cer") * 100).toFixed(1)}%  mean latency ${Math.round(avg("ms"))} ms  RTF ${(avg("ms") / 1000 / avg("audioSeconds")).toFixed(2)}  n=${ok.length}`);
}
const out = process.env.OUT ?? join(dir, `stt-benchmark-${new Date().toISOString().slice(0, 10)}.json`);
await writeFile(out, JSON.stringify({ at: new Date().toISOString(), lang, keyterms, rows }, null, 2));
console.log(`\nreport: ${out}`);

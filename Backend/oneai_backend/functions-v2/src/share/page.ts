import { FieldValue } from "firebase-admin/firestore";
import type { Deps } from "../lib/deps.js";
import { log } from "../lib/logging.js";
import { toSummary, toTranscript, toSpeakers } from "../minutes/_shared.js";
import type { Summary, Transcript } from "../minutes/types.js";
import { pdfFileName, renderNotePdf } from "./pdf.js";
import type { ShareDoc } from "./types.js";

export interface PageResult { status: number; html: string; pdf?: { bytes: Buffer; fileName: string }; json?: SharedNote }

/** What the app's in-app viewer (deep link `/s?t=`) and `importSharedNote` read. */
export interface SharedNote {
  token: string;
  title: string;
  iconEmoji: string | null;
  createdAt: string;
  sourceType: string;
  summary: Summary | null;
  transcript: Transcript | null;
  speakers: { id: string; label: string }[];
  pdfUrl: string;
}

/** Resolves a live token to its note, or null when it is invalid / revoked / gone. Never counts a view. */
export async function loadShared(deps: Deps, token: string | undefined): Promise<{ share: ShareDoc; shareRef: FirebaseFirestore.DocumentReference; note: SharedNote; minute: Record<string, unknown> } | null> {
  if (!token || !/^[A-Za-z0-9_-]{16,64}$/.test(token)) return null;
  const shareSnap = await deps.db.collection("shares").doc(token).get();
  const share = shareSnap.data() as ShareDoc | undefined;
  if (!shareSnap.exists || !share || share.revokedAt) return null;
  const minuteRef = deps.db.doc(`users/${share.uid}/minutes/${share.minuteId}`);
  const [minuteSnap, speakersSnap] = await Promise.all([minuteRef.get(), minuteRef.collection("artifacts").doc("speakers").get()]);
  const m = minuteSnap.data() as Record<string, unknown> | undefined;
  if (!minuteSnap.exists || !m || m.status !== "ready" || m.shareToken !== token) return null;
  let transcript: Transcript | null = null;
  if (share.includeTranscript && typeof m.transcriptPath === "string") {
    try {
      const [buf] = await deps.bucket.file(m.transcriptPath).download();
      transcript = toTranscript(JSON.parse(buf.toString("utf8")));
    } catch (err) {
      log.warn("share.transcript_unreadable", { minuteId: share.minuteId, error: String(err) });
    }
  }
  const speakers = toSpeakers((speakersSnap.data() as { data?: unknown } | undefined)?.data).map((s) => ({ id: s.id, label: s.label }));
  const createdAt = m.createdAt && typeof (m.createdAt as { toDate?: unknown }).toDate === "function" ? (m.createdAt as { toDate: () => Date }).toDate().toISOString().slice(0, 10) : "";
  const note: SharedNote = {
    token,
    title: typeof m.title === "string" ? m.title : "Untitled",
    iconEmoji: typeof m.iconEmoji === "string" ? m.iconEmoji : null,
    createdAt,
    sourceType: typeof m.sourceType === "string" ? m.sourceType : "audio",
    summary: toSummary(m.summary),
    transcript,
    speakers,
    pdfUrl: `${deps.shareBaseUrl}${deps.shareBaseUrl.includes("?") ? "&" : "?"}t=${token}&format=pdf`,
  };
  return { share, shareRef: shareSnap.ref, note, minute: m };
}

export const esc = (s: string): string =>
  s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" })[c] ?? c);

const STYLE = `body{margin:0;background:#f6f8fb;color:#1a1a1a;font:16px/1.55 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif}
main{max-width:720px;margin:0 auto;padding:32px 20px 64px}h1{font-size:26px;margin:0 0 4px}h2{font-size:17px;margin:28px 0 8px}
.meta{color:#666;font-size:13px;margin-bottom:20px}.card{background:#fff;border:1px solid #e3e8ef;border-radius:12px;padding:20px 22px}
ul{padding-left:20px;margin:0}li{margin:4px 0}li.sub{list-style:circle;margin-left:18px}p.text{white-space:pre-wrap}
.seg{margin:8px 0}.spk{font-weight:600;color:#0767f8}footer{margin-top:32px;color:#888;font-size:12px;text-align:center}
a.pdf{color:#0767f8;font-weight:600;text-decoration:none}a.pdf:hover{text-decoration:underline}`;

function bulletsHtml(bullets: string[]): string {
  return `<ul>${bullets.map((b) => {
    const sub = b.startsWith("    ◦ ");
    const text = b.replace(/^(• |    ◦ )/, "");
    return `<li${sub ? " class=\"sub\"" : ""}>${esc(text)}</li>`;
  }).join("")}</ul>`;
}

export function renderPage(opts: { title: string; iconEmoji: string | null; createdAt: string; summary: Summary | null; transcript: Transcript | null; speakerLabels: Map<string, string>; pdfHref?: string }): string {
  const s = opts.summary;
  const body: string[] = [];
  body.push(`<h1>${opts.iconEmoji ? esc(opts.iconEmoji) + " " : ""}${esc(opts.title)}</h1>`);
  body.push(`<div class="meta">${esc(opts.createdAt)}${opts.pdfHref ? ` · <a class="pdf" href="${esc(opts.pdfHref)}">Download PDF</a>` : ""}</div>`);
  if (s) {
    body.push(`<div class="card">`);
    if (s.text) body.push(`<p class="text">${esc(s.text)}</p>`);
    for (const sec of s.sections) {
      if (sec.bullets.length === 0) continue;
      body.push(`<h2>${esc(sec.title)}</h2>${bulletsHtml(sec.bullets)}`);
    }
    body.push(`</div>`);
  }
  if (opts.transcript) {
    body.push(`<h2>Transcript</h2><div class="card">`);
    for (const seg of opts.transcript.segments) {
      const who = opts.speakerLabels.get(seg.speakerId) ?? seg.speakerLabel ?? seg.speakerId;
      body.push(`<div class="seg"><span class="spk">${esc(who)}:</span> ${esc(seg.text)}</div>`);
    }
    body.push(`</div>`);
  }
  body.push(`<footer>Shared read-only from One AI · the owner can revoke this link at any time.</footer>`);
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex,nofollow"><title>${esc(opts.title)}</title><style>${STYLE}</style></head><body><main>${body.join("")}</main></body></html>`;
}

export function notFoundPage(): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>Link unavailable</title><style>${STYLE}</style></head><body><main><div class="card"><h1>This link is no longer available</h1><p>The note was deleted or its owner revoked the link.</p></div></main></body></html>`;
}

/** Pure-ish: everything the HTTP wrapper needs, testable without Express. */
export async function sharePage(deps: Deps, token: string | undefined, opts: { format?: "html" | "pdf" | "json" } = {}): Promise<PageResult> {
  const loaded = await loadShared(deps, token);
  if (!loaded) return { status: 404, html: notFoundPage() };
  const { note, shareRef } = loaded;

  // Best-effort view counter; never delays or fails the page.
  void shareRef.update({ views: FieldValue.increment(1), lastViewedAt: FieldValue.serverTimestamp() }).catch(() => undefined);

  if (opts.format === "json") return { status: 200, html: "", json: note };
  const title = note.title;
  const content = { title, iconEmoji: note.iconEmoji, createdAt: note.createdAt, summary: note.summary, transcript: note.transcript, speakerLabels: new Map(note.speakers.map((s) => [s.id, s.label])) };
  if (opts.format === "pdf") {
    const bytes = await renderNotePdf({ ...content, footer: "Shared from One AI · read-only" });
    return { status: 200, html: "", pdf: { bytes, fileName: pdfFileName(title) } };
  }
  return { status: 200, html: renderPage({ ...content, pdfHref: `?t=${encodeURIComponent(note.token)}&format=pdf` }) };
}

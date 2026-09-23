import { fileURLToPath } from "node:url";
import PDFDocument from "pdfkit";
import type { Summary, Transcript } from "../minutes/types.js";

/**
 * Server-side PDF of a note (S11-05, decided 24/09: a shared note is
 * delivered as a PDF). Noto Sans is embedded because pdfkit's built-in
 * Helvetica has no Vietnamese glyphs. Same content order as the HTML page
 * and as the app's local export: title · date · narrative · sections ·
 * (transcript) · footer.
 */
const FONT_REGULAR = fileURLToPath(new URL("../../assets/fonts/NotoSans-Regular.ttf", import.meta.url));
const FONT_BOLD = fileURLToPath(new URL("../../assets/fonts/NotoSans-Bold.ttf", import.meta.url));

export interface NotePdfInput {
  title: string;
  iconEmoji: string | null;
  createdAt: string;
  summary: Summary | null;
  transcript: Transcript | null;
  speakerLabels: Map<string, string>;
  /** Shown in the footer, e.g. the share URL. */
  footer?: string;
}

const BLUE = "#0767F8";
const INK = "#1a1a1a";
const MUTED = "#666666";

export function renderNotePdf(input: NotePdfInput): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({
      size: "A4",
      margins: { top: 56, bottom: 56, left: 56, right: 56 },
      info: { Title: input.title, Author: "One AI", Producer: "One AI" },
      compress: true,
    });
    const chunks: Buffer[] = [];
    doc.on("data", (c: Buffer) => chunks.push(c));
    doc.on("end", () => resolve(Buffer.concat(chunks)));
    doc.on("error", reject);

    doc.registerFont("body", FONT_REGULAR);
    doc.registerFont("bold", FONT_BOLD);

    // Emoji are not in Noto Sans; keep the title clean rather than boxes.
    doc.font("bold").fontSize(20).fillColor(INK).text(input.title, { lineGap: 2 });
    doc.moveDown(0.2);
    doc.font("body").fontSize(10).fillColor(MUTED).text(input.createdAt);
    doc.moveDown(0.8);

    const s = input.summary;
    if (s) {
      if (s.text) {
        doc.font("body").fontSize(11).fillColor(INK).text(s.text, { lineGap: 3 });
        doc.moveDown(0.8);
      }
      for (const sec of s.sections) {
        if (sec.bullets.length === 0) continue;
        doc.font("bold").fontSize(13).fillColor(BLUE).text(sec.title, { lineGap: 2 });
        doc.moveDown(0.25);
        for (const b of sec.bullets) {
          const sub = b.startsWith("    ◦ ");
          const text = b.replace(/^(• |    ◦ )/, "");
          doc.font("body").fontSize(11).fillColor(INK).text(`${sub ? "◦" : "•"} ${text}`, { indent: sub ? 24 : 6, lineGap: 2 });
        }
        doc.moveDown(0.7);
      }
    }

    if (input.transcript) {
      doc.addPage();
      doc.font("bold").fontSize(13).fillColor(BLUE).text("Transcript");
      doc.moveDown(0.4);
      for (const seg of input.transcript.segments) {
        const who = input.speakerLabels.get(seg.speakerId) ?? seg.speakerLabel ?? seg.speakerId;
        doc.font("bold").fontSize(10.5).fillColor(BLUE).text(`${who}: `, { continued: true });
        doc.font("body").fontSize(10.5).fillColor(INK).text(seg.text, { lineGap: 2 });
        doc.moveDown(0.3);
      }
    }

    // Footer on every page.
    const range = doc.bufferedPageRange();
    for (let i = range.start; i < range.start + range.count; i++) {
      doc.switchToPage(i);
      const y = doc.page.height - 40;
      doc.font("body").fontSize(8).fillColor(MUTED)
        .text(`${input.footer ?? "Shared from One AI"} · ${i - range.start + 1}/${range.count}`, 56, y, { width: doc.page.width - 112, align: "center", lineBreak: false });
    }
    doc.end();
  });
}

/** Windows/iOS-safe attachment name. */
export function pdfFileName(title: string): string {
  const safe = title.replace(/đ/g, "d").replace(/Đ/g, "D").normalize("NFKD").replace(/[^\w\s-]/g, "").trim().replace(/\s+/g, "-").slice(0, 60);
  return `${safe || "note"}.pdf`;
}

import { createRequire } from "node:module";
import { HttpsError } from "firebase-functions/v2/https";

// pdf-parse 1.x is CommonJS; load it via require from ESM.
const require = createRequire(import.meta.url);
const pdfParse = require("pdf-parse") as (data: Buffer) => Promise<{ text: string; numpages: number }>;

export const MAX_PDF_TEXT_CHARS = 400_000;

export async function pdfText(bytes: Uint8Array): Promise<string> {
  let out: { text: string; numpages: number };
  try {
    out = await pdfParse(Buffer.from(bytes));
  } catch {
    throw new HttpsError("invalid-argument", "This PDF could not be read", { field: "file", reason: "pdfUnreadable" });
  }
  const text = out.text.replace(/\r\n/g, "\n").replace(/[ \t]+\n/g, "\n").trim();
  if (text.length === 0) {
    throw new HttpsError("failed-precondition", "This PDF contains no extractable text", { reason: "pdfNoText" });
  }
  return text.slice(0, MAX_PDF_TEXT_CHARS);
}

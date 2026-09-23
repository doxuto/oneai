import { onRequest } from "firebase-functions/v2/https";
import { liveDeps } from "../lib/deps.js";
import { sharePage } from "./page.js";

/**
 * PUBLIC read-only page for a share token (S11-05). `&format=pdf` returns the
 * note as a PDF attachment (decided 24/09: shared notes are PDFs). No auth, no App Check —
 * the unguessable token is the credential; the owner revokes it in the app.
 * Served straight from the function so no Hosting setup is needed; point a
 * custom domain at it later via SHARE_BASE_URL.
 */
export const sharePage_ = onRequest(
  { memory: "256MiB", timeoutSeconds: 30, maxInstances: 10, cors: false },
  async (req, res) => {
    if (req.method !== "GET" && req.method !== "HEAD") { res.status(405).send("Method Not Allowed"); return; }
    const t = typeof req.query.t === "string" ? req.query.t : undefined;
    const format = req.query.format === "pdf" ? "pdf" : "html";
    const out = await sharePage(liveDeps(), t, { format });
    if (out.pdf) {
      res.status(200)
        .set("Cache-Control", "private, no-store")
        .set("X-Robots-Tag", "noindex, nofollow")
        .set("Content-Disposition", `attachment; filename="${out.pdf.fileName}"`)
        .type("application/pdf")
        .send(out.pdf.bytes);
      return;
    }
    res.status(out.status)
      .set("Cache-Control", "private, no-store")
      .set("X-Robots-Tag", "noindex, nofollow")
      .set("Referrer-Policy", "no-referrer")
      .type("html")
      .send(out.html);
  },
);
export { sharePage_ as sharePage };

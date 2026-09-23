import { readFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";
import { onRequest } from "firebase-functions/v2/https";

/**
 * PUBLIC legal pages (S10-07): Privacy Policy, Terms of Service and the
 * account-deletion instructions Google Play requires, in English and
 * Vietnamese, served straight from the function so the links in the app
 * work before any website exists. `?doc=privacy|terms|delete-account&lang=en|vi`.
 * Point doxutostudio.top at these (or copy the HTML) when the site is ready.
 */
const DOCS = new Set(["privacy", "terms", "delete-account"]);
const LANGS = new Set(["en", "vi"]);
const dir = new URL("../../assets/legal/", import.meta.url);

export function pickDoc(q: Record<string, unknown>): { doc: string; lang: string } | { asset: "style" } | null {
  if (q.asset === "style") return { asset: "style" };
  const doc = typeof q.doc === "string" && DOCS.has(q.doc) ? q.doc : "privacy";
  const raw = typeof q.lang === "string" ? q.lang.toLowerCase().slice(0, 2) : "en";
  const lang = LANGS.has(raw) ? raw : "en";
  return { doc, lang };
}

export const legal = onRequest(
  { memory: "128MiB", timeoutSeconds: 10, maxInstances: 5, cors: false },
  async (req, res) => {
    if (req.method !== "GET" && req.method !== "HEAD") { res.status(405).send("Method Not Allowed"); return; }
    const pick = pickDoc(req.query as Record<string, unknown>);
    if (pick && "asset" in pick) {
      res.status(200).set("Cache-Control", "public, max-age=86400").type("text/css").send(await readFile(fileURLToPath(new URL("_style.css", dir)), "utf8"));
      return;
    }
    const { doc, lang } = pick ?? { doc: "privacy", lang: "en" };
    const html = await readFile(fileURLToPath(new URL(`${doc}.${lang}.html`, dir)), "utf8");
    res.status(200).set("Cache-Control", "public, max-age=3600").set("X-Robots-Tag", "all").type("html").send(html);
  },
);

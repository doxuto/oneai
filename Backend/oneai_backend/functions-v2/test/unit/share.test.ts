import { describe, expect, it } from "vitest";
import { unitDeps } from "../../src/lib/deps.js";
import { createShareLinkHandler, newShareToken, revokeShareLinkHandler, shareUrl } from "../../src/share/handler.js";
import { esc, notFoundPage, renderPage, sharePage } from "../../src/share/page.js";
import { CreateShareLinkInput } from "../../src/share/types.js";

const client = { appVersion: "2.0.0", build: 1, platform: "ios" as const };
const caller = { uid: "u1", signInProvider: "google.com" };

describe("share links (S11-05)", () => {
  it("tokens are 32 url-safe chars and unique", () => {
    const a = newShareToken();
    const b = newShareToken();
    expect(a).toMatch(/^[A-Za-z0-9_-]{32}$/);
    expect(a).not.toBe(b);
  });
  it("shareUrl appends ?t= or &t=", () => {
    expect(shareUrl("https://x.test/s", "abc")).toBe("https://x.test/s?t=abc");
    expect(shareUrl("https://x.test/s?v=1", "abc")).toBe("https://x.test/s?v=1&t=abc");
  });
  it("input: includeTranscript defaults false; unknown keys rejected", () => {
    expect(CreateShareLinkInput.parse({ client, minuteId: "m1" }).includeTranscript).toBe(false);
    expect(() => CreateShareLinkInput.parse({ client, minuteId: "m1", public: true })).toThrow();
  });
  it("handlers require auth before touching db", async () => {
    await expect(createShareLinkHandler(undefined, { client, minuteId: "m1" }, unitDeps())).rejects.toMatchObject({ code: "unauthenticated" });
    await expect(revokeShareLinkHandler(undefined, { client, minuteId: "m1" }, unitDeps())).rejects.toMatchObject({ code: "unauthenticated" });
    await expect(createShareLinkHandler(caller, { client, minuteId: "a/b" }, unitDeps())).rejects.toMatchObject({ code: "invalid-argument" });
  });
  it("sharePage rejects a malformed token without a db read", async () => {
    for (const t of [undefined, "", "short", "has space here and is long", "<script>alert(1)</script>xxxxxxxxxx"]) {
      const out = await sharePage(unitDeps(), t);
      expect(out.status).toBe(404);
      expect(out.html).toBe(notFoundPage());
    }
  });
  it("renderPage escapes user content and renders two bullet levels", () => {
    const html = renderPage({
      title: "<b>Standup</b>", iconEmoji: "📝", createdAt: "2026-09-23",
      summary: { title: "S", text: "a & b", icon: null, sections: [{ title: "Topic <1>", bullets: ["• one", "    ◦ two"] }, { title: "Empty", bullets: [] }] },
      transcript: { durationSeconds: 1, text: "hi", languageCode: "en", languageProbability: 1, segments: [{ startSeconds: 0, endSeconds: 1, text: "hi <you>", speakerId: "speaker_0", speakerLabel: "Speaker 1" }] },
      speakerLabels: new Map([["speaker_0", "Ana"]]),
    });
    expect(html).not.toContain("<b>Standup</b>");
    expect(html).toContain("&lt;b&gt;Standup&lt;/b&gt;");
    expect(html).toContain("a &amp; b");
    expect(html).toContain("Topic &lt;1&gt;");
    expect(html).toContain('<li>one</li>');
    expect(html).toContain('<li class="sub">two</li>');
    expect(html).not.toContain("Empty");
    expect(html).toContain("Ana:</span> hi &lt;you&gt;");
    expect(html).toContain('name="robots" content="noindex');
    expect(esc("'\"")).toBe("&#39;&quot;");
  });
});

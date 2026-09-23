import { getStorage } from "firebase-admin/storage";
import { Timestamp } from "firebase-admin/firestore";
import { beforeEach, describe, expect, it } from "vitest";
import { unitDeps, type Deps } from "../../src/lib/deps.js";
import { deleteMinuteHandler, getMinuteHandler } from "../../src/minutes/handler.js";
import { createShareLinkHandler, revokeShareLinkHandler } from "../../src/share/handler.js";
import { sharePage } from "../../src/share/page.js";
import { wipeUser } from "../../src/users/lifecycle.js";
import { clearFirestore, fixedNow, testDb } from "../helpers/emulator.js";

const db = testDb();
const bucket = getStorage().bucket("demo-oneai.appspot.com");
const deps: Deps = unitDeps({ db, bucket: bucket as Deps["bucket"], now: fixedNow() });
const client = { appVersion: "2.0.0", build: 1, platform: "ios" as const };
const u1 = { uid: "u1", signInProvider: "google.com" };
const u2 = { uid: "u2", signInProvider: "apple.com" };

const transcript = {
  durationSeconds: 4, languageCode: "en", languageProbability: 0.9, text: "Hello everyone. Sure.",
  segments: [
    { startSeconds: 0, endSeconds: 2, text: "Hello everyone.", speakerId: "speaker_0", speakerLabel: "Speaker 1" },
    { startSeconds: 2, endSeconds: 4, text: "Sure.", speakerId: "speaker_1", speakerLabel: "Speaker 2" },
  ],
};

async function seedReady(uid = "u1", id = "m1", extra: Record<string, unknown> = {}) {
  await bucket.file(`users/${uid}/minutes/${id}/transcript.json`).save(JSON.stringify(transcript), { resumable: false });
  await db.doc(`users/${uid}/minutes/${id}`).set({
    title: "Standup <1>", iconEmoji: "📝", status: "ready", sourceType: "audio", tagIds: [],
    transcriptPath: `users/${uid}/minutes/${id}/transcript.json`,
    summary: { title: "S", text: "We synced.", icon: null, sections: [{ title: "Decisions", bullets: ["• Ship Friday"] }] },
    createdAt: Timestamp.fromDate(new Date("2026-09-01T00:00:00Z")), updatedAt: Timestamp.fromDate(new Date("2026-09-01T00:00:00Z")),
    ...extra,
  });
}

const tokenOf = (url: string) => new URL(url).searchParams.get("t")!;

describe("share links (S11-05)", () => {
  beforeEach(async () => { await clearFirestore(); const [f] = await bucket.getFiles({ prefix: "users/" }); await Promise.all(f.map((x) => x.delete())); });

  it("create → public page renders the summary; getMinute exposes the link; views count", async () => {
    await seedReady();
    const { share } = await createShareLinkHandler(u1, { client, minuteId: "m1" }, deps);
    expect(share.url).toMatch(/^https:\/\/share\.test\/s\?t=[A-Za-z0-9_-]{32}$/);
    expect(share).toMatchObject({ includeTranscript: false, views: 0 });

    const page = await sharePage(deps, tokenOf(share.url));
    expect(page.status).toBe(200);
    expect(page.html).toContain("Standup &lt;1&gt;");
    expect(page.html).toContain("Ship Friday");
    expect(page.html).not.toContain("Hello everyone"); // transcript not included
    await new Promise((r) => setTimeout(r, 50)); // best-effort counter
    expect((await db.doc(`shares/${tokenOf(share.url)}`).get()).data()?.views).toBe(1);

    const { minute } = await getMinuteHandler(u1, { client, minuteId: "m1" }, deps);
    expect(minute.share?.url).toBe(share.url);

    // Decided 24/09: the shared note is a PDF; the page links to it.
    expect(page.html).toContain("format=pdf");
    const pdf = await sharePage(deps, tokenOf(share.url), { format: "pdf" });
    expect(pdf.status).toBe(200);
    expect(pdf.pdf?.fileName).toBe("Standup-1.pdf");
    expect(pdf.pdf?.bytes.subarray(0, 5).toString()).toBe("%PDF-");
  });

  it("is idempotent for the same options and rotates the token when includeTranscript changes", async () => {
    await seedReady();
    const a = (await createShareLinkHandler(u1, { client, minuteId: "m1" }, deps)).share;
    const b = (await createShareLinkHandler(u1, { client, minuteId: "m1" }, deps)).share;
    expect(b.url).toBe(a.url);
    const c = (await createShareLinkHandler(u1, { client, minuteId: "m1", includeTranscript: true }, deps)).share;
    expect(c.url).not.toBe(a.url);
    expect((await sharePage(deps, tokenOf(a.url))).status).toBe(404); // old token revoked
    const page = await sharePage(deps, tokenOf(c.url));
    expect(page.status).toBe(200);
    expect(page.html).toContain("Hello everyone.");
    expect(page.html).toContain("Speaker 1:</span>");
  });

  it("revoke → 404; deleting the note or the user removes the share doc", async () => {
    await seedReady();
    const t1 = tokenOf((await createShareLinkHandler(u1, { client, minuteId: "m1" }, deps)).share.url);
    await revokeShareLinkHandler(u1, { client, minuteId: "m1" }, deps);
    expect((await sharePage(deps, t1)).status).toBe(404);
    expect((await getMinuteHandler(u1, { client, minuteId: "m1" }, deps)).minute.share).toBeNull();
    await revokeShareLinkHandler(u1, { client, minuteId: "m1" }, deps); // no link → no-op

    const t2 = tokenOf((await createShareLinkHandler(u1, { client, minuteId: "m1" }, deps)).share.url);
    await deleteMinuteHandler(u1, { client, minuteId: "m1" }, deps);
    expect((await db.doc(`shares/${t2}`).get()).exists).toBe(false);

    await seedReady("u1", "m2");
    const t3 = tokenOf((await createShareLinkHandler(u1, { client, minuteId: "m2" }, deps)).share.url);
    await wipeUser(deps, "u1");
    expect((await db.doc(`shares/${t3}`).get()).exists).toBe(false);
  });

  it("refuses a note that is not ready, another user's note, and a token whose note no longer matches", async () => {
    await seedReady("u1", "m1", { status: "transcribing" });
    await expect(createShareLinkHandler(u1, { client, minuteId: "m1" }, deps)).rejects.toMatchObject({ code: "failed-precondition" });
    await seedReady("u1", "m1");
    await expect(createShareLinkHandler(u2, { client, minuteId: "m1" }, deps)).rejects.toMatchObject({ code: "not-found" });
    const t = tokenOf((await createShareLinkHandler(u1, { client, minuteId: "m1" }, deps)).share.url);
    await db.doc("users/u1/minutes/m1").update({ shareToken: "something-else-entirely-1234567890" });
    expect((await sharePage(deps, t)).status).toBe(404);
  });
});

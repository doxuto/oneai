#!/usr/bin/env node
/**
 * Seed the emulator with a signed-in demo user, tags and notes in every
 * status, so the app can be developed against `firebase emulators:start`
 * without transcribing anything.
 *
 *   npm run build
 *   firebase emulators:start --only auth,firestore,storage --project demo-oneai
 *   node tools/seed-emulator.mjs          # in another terminal
 *
 * Sign in the app with:  demo@oneai.local / demo1234   (Auth emulator)
 */
import { getApps, initializeApp } from "firebase-admin/app";
import { getAuth } from "firebase-admin/auth";
import { FieldValue, Timestamp, getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

for (const v of ["FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST", "FIREBASE_STORAGE_EMULATOR_HOST"]) {
  if (!process.env[v]) process.env[v] = { FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080", FIREBASE_AUTH_EMULATOR_HOST: "127.0.0.1:9099", FIREBASE_STORAGE_EMULATOR_HOST: "127.0.0.1:9199" }[v];
}
if (getApps().length === 0) initializeApp({ projectId: "demo-oneai", storageBucket: "demo-oneai.appspot.com" });
const db = getFirestore(); const auth = getAuth(); const bucket = getStorage().bucket();

const email = "demo@oneai.local";
let user;
try { user = await auth.getUserByEmail(email); } catch { user = await auth.createUser({ email, password: "demo1234", displayName: "Demo User" }); }
const uid = user.uid;
const daysAgo = (d) => Timestamp.fromDate(new Date(Date.now() - d * 86400000));
const period = new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Ho_Chi_Minh", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());

await db.doc(`users/${uid}`).set({ email, displayName: "Demo User", photoUrl: null, plan: "free", planExpiresAt: null, minuteCount: 4, createdAt: daysAgo(30), updatedAt: FieldValue.serverTimestamp() }, { merge: true });
await db.doc(`users/${uid}/quota/${period}`).set({ periodId: period, used: 0, baseLimit: 1, rewardBonus: 1, aiCalls: 0, expiresAt: new Date(Date.now() + 3 * 86400000) });
await db.doc(`users/${uid}/tags/work`).set({ name: "Work", nameLower: "work", minuteCount: 2, createdAt: daysAgo(20) });
await db.doc(`users/${uid}/tags/study`).set({ name: "Study", nameLower: "study", minuteCount: 1, createdAt: daysAgo(10) });

const transcript = {
  durationSeconds: 95.4, languageCode: "eng", languageProbability: 0.98,
  text: "Good morning everyone. Let's go over the sprint. Sure — the API is done, the app side starts Monday. Great, then we ship on the 15th.",
  segments: [
    { startSeconds: 0, endSeconds: 6.2, text: "Good morning everyone. Let's go over the sprint.", speakerId: "speaker_0", speakerLabel: "Speaker 1" },
    { startSeconds: 7.1, endSeconds: 14.8, text: "Sure — the API is done, the app side starts Monday.", speakerId: "speaker_1", speakerLabel: "Speaker 2" },
    { startSeconds: 15.5, endSeconds: 20.0, text: "Great, then we ship on the 15th.", speakerId: "speaker_0", speakerLabel: "Speaker 1" },
  ],
};
const base = (over) => ({ iconEmoji: null, sourceType: "audio", contentKind: null, statusUpdatedAt: FieldValue.serverTimestamp(), failure: null, durationSeconds: null, sourcePath: null, sourceContentType: "audio/x-m4a", languageCode: null, languageProbability: null, summaryLanguage: "en", keywords: [], description: null, tagIds: [], summary: null, transcriptPath: null, transcriptPreview: null, updatedAt: FieldValue.serverTimestamp(), ...over });

await bucket.file(`users/${uid}/minutes/ready1/transcript.json`).save(JSON.stringify(transcript), { contentType: "application/json", resumable: false });
await db.doc(`users/${uid}/minutes/ready1`).set(base({
  title: "Sprint planning", iconEmoji: "🗓️", contentKind: "team_meeting", status: "ready", durationSeconds: 95.4, languageCode: "eng", languageProbability: 0.98,
  tagIds: ["work"], keywords: ["sprint", "API"], createdAt: daysAgo(2),
  summary: { title: "Sprint planning", text: "The API is finished; app work starts Monday; ship date is the 15th.", icon: "🗓️", sections: [{ title: "Overview", bullets: ["• API done, app starts Monday, ship on the 15th."] }, { title: "Decisions", bullets: ["• Ship on the 15th.", "    ◦ App side begins Monday."] }] },
  transcriptPath: `users/${uid}/minutes/ready1/transcript.json`, transcriptPreview: transcript.text,
}));
await db.doc(`users/${uid}/minutes/ready1/artifacts/speakers`).set({ kind: "speakers", data: { speakers: [{ id: "speaker_0", label: "Ana" }, { id: "speaker_1", label: "speaker_1" }] }, model: "seed", sourceHash: "seed", generatedAt: FieldValue.serverTimestamp() });
await db.doc(`users/${uid}/minutes/ready1/chat/c1`).set({ role: "user", text: "When do we ship?", createdAt: daysAgo(1) });
await db.doc(`users/${uid}/minutes/ready1/chat/c2`).set({ role: "assistant", text: "On the 15th.", createdAt: daysAgo(1) });

await db.doc(`users/${uid}/minutes/ready2`).set(base({ title: "Lecture 3 — Graphs", iconEmoji: "📚", contentKind: "lecture", status: "ready", durationSeconds: 3120, tagIds: ["study", "work"], createdAt: daysAgo(7), summary: { title: "Graphs", text: "BFS and DFS.", icon: "📚", sections: [] } }));
await db.doc(`users/${uid}/minutes/processing`).set(base({ title: "Standup 23-09", status: "transcribing", createdAt: daysAgo(0) }));
await db.doc(`users/${uid}/minutes/failed`).set(base({ title: "Long recording", status: "failed", failure: { code: "failed-precondition", message: "This recording is longer than your plan allows." }, createdAt: daysAgo(1) }));

console.log(`seeded uid=${uid}  sign in: ${email} / demo1234`);

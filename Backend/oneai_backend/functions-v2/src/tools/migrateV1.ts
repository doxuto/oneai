/**
 * v1 → v2 data migration, one user at a time, idempotent, dry-run by default.
 *
 * v1 layout (docs/01 §2)                       v2 layout (docs/06)
 * ──────────────────────────────────────────── ──────────────────────────────────────────
 * users/{uid}                                  users/{uid}  (+photoUrl, planExpiresAt, minuteCount)
 * users/{uid}/minutes/{id}                     same doc, fields reshaped, status derived
 *   metadata/transcription {sections[timeRange]} → Storage transcript.json {segments[seconds]}
 *   metadata/summary                           → minute.summary (embedded)
 *   metadata/{speakers,quiz,flashcards,        → artifacts/{kind} {kind,data,sourceHash}
 *             mindmap,shortQuestions,calendarEvents}
 * tags/{uid}/tagItems/{id} {name,name_lower}   → users/{uid}/tags/{id} {name,nameLower,minuteCount}
 * Storage user_uploads/{uid}/{id}/audio/*      → referenced in place as sourcePath (rules keep it readable)
 */
import { createHash } from "node:crypto";
import { FieldValue, Timestamp, type DocumentData, type Firestore } from "firebase-admin/firestore";
import type { Bucket } from "../lib/admin.js";
import { previewOf } from "../lib/stt/convert.js";
import { transcriptPath } from "../minutes/_shared.js";
import type { Transcript, TranscriptSegment } from "../minutes/types.js";
import { nameKey } from "../tags/_shared.js";

export interface MigrateOptions {
  dryRun: boolean;
  /** Re-migrate minutes that already carry migratedAt. */
  force: boolean;
  log?: (line: string) => void;
}

export interface MigrateReport {
  users: number;
  minutes: number;
  minutesReady: number;
  minutesFailed: number;
  minutesSkipped: number;
  tags: number;
  artifacts: number;
  transcriptsWritten: number;
  warnings: string[];
}

const noop = () => undefined;

// ---------- pure converters (unit-tested) ----------

/** "MM:SS" | "HH:MM:SS" → seconds. Anything else → null. */
export function parseClock(s: unknown): number | null {
  if (typeof s !== "string") return null;
  const parts = s.trim().split(":").map((p) => Number.parseInt(p, 10));
  if (parts.some((n) => !Number.isFinite(n))) return null;
  if (parts.length === 2) return (parts[0] ?? 0) * 60 + (parts[1] ?? 0);
  if (parts.length === 3) return (parts[0] ?? 0) * 3600 + (parts[1] ?? 0) * 60 + (parts[2] ?? 0);
  return null;
}

/** v1 `metadata/transcription` doc → v2 Transcript. */
export function convertV1Transcription(raw: DocumentData | undefined): Transcript | null {
  if (!raw) return null;
  const sections = Array.isArray(raw.sections) ? raw.sections : [];
  const segments: TranscriptSegment[] = [];
  for (const s of sections) {
    if (!s || typeof s !== "object") continue;
    const sec = s as Record<string, unknown>;
    const [a, b] = typeof sec.timeRange === "string" ? sec.timeRange.split("-").map((x) => x.trim()) : [];
    const speakerId = typeof sec.speaker_id === "string" ? sec.speaker_id : "speaker_0";
    const n = /\d+/.exec(speakerId)?.[0];
    segments.push({
      startSeconds: parseClock(a) ?? 0,
      endSeconds: parseClock(b) ?? 0,
      text: typeof sec.title === "string" ? sec.title : "",
      speakerId,
      speakerLabel: typeof sec.speaker === "string" ? sec.speaker : n ? `Speaker ${Number(n) + 1}` : speakerId,
    });
  }
  const text = typeof raw.transcript === "string" && raw.transcript.length > 0 ? raw.transcript : segments.map((x) => x.text).join(" ");
  if (!text) return null;
  return {
    durationSeconds: parseClock(raw.duration) ?? segments.at(-1)?.endSeconds ?? 0,
    languageCode: typeof raw.language_code === "string" ? raw.language_code : null,
    languageProbability: typeof raw.language_probability === "number" ? raw.language_probability : null,
    text,
    segments,
  };
}

export function convertV1Summary(raw: DocumentData | undefined) {
  if (!raw) return null;
  const sections = Array.isArray(raw.sections)
    ? raw.sections.filter((x: unknown): x is Record<string, unknown> => !!x && typeof x === "object").map((x) => ({
        title: typeof x.title === "string" ? x.title : "",
        bullets: Array.isArray(x.bullets) ? x.bullets.filter((b: unknown): b is string => typeof b === "string") : [],
      }))
    : [];
  return {
    title: typeof raw.title === "string" ? raw.title : "",
    text: typeof raw.summaryText === "string" ? raw.summaryText : "",
    icon: typeof raw.icon === "string" ? raw.icon : null,
    sections,
  };
}

/** v1 metadata docs → v2 artifact `data`, per kind. Returns null when nothing usable. */
export function convertV1Artifact(kind: string, raw: DocumentData | undefined): unknown {
  if (!raw) return null;
  switch (kind) {
    case "speakers": {
      const speakers = Object.entries(raw)
        .filter(([k, v]) => /^speaker_\d+$/.test(k) && typeof v === "string")
        .map(([id, label]) => ({ id, label: label as string }));
      return speakers.length ? { speakers } : null;
    }
    case "shortQuestions": {
      const q = Array.isArray(raw.short_questions) ? raw.short_questions.filter((x: unknown): x is string => typeof x === "string") : [];
      return q.length ? { questions: q.slice(0, 10) } : null;
    }
    case "quiz": {
      const items: { question: string; options: string[]; answerIndex: number }[] = [];
      for (const it of Array.isArray(raw.quiz) ? raw.quiz : []) {
        if (!it || typeof it !== "object") continue;
        const q = it as Record<string, unknown>;
        const question = typeof q.question === "string" ? q.question : "";
        const answer = typeof q.answer === "string" ? q.answer : "";
        let options = Array.isArray(q.options) ? q.options.filter((o: unknown): o is string => typeof o === "string") : [];
        if (options.length < 2) {
          if (/^(true|false)$/i.test(answer)) options = ["True", "False"];
          else continue; // short-answer items have no v2 shape
        }
        const idx = options.findIndex((o) => o.trim().toLowerCase() === answer.trim().toLowerCase());
        if (!question || idx < 0) continue;
        items.push({ question, options: options.slice(0, 4), answerIndex: idx });
      }
      return items.length ? { items: items.slice(0, 15) } : null;
    }
    case "flashcards": {
      const items = (Array.isArray(raw.flashcards) ? raw.flashcards : [])
        .filter((x: unknown): x is { question: string; answer: string } => !!x && typeof x === "object" && typeof (x as Record<string, unknown>).question === "string" && typeof (x as Record<string, unknown>).answer === "string")
        .map((x: { question: string; answer: string }) => ({ question: x.question, answer: x.answer }));
      return items.length ? { items: items.slice(0, 15) } : null;
    }
    case "mindmap": {
      const m = raw.mindmap as Record<string, unknown> | undefined;
      if (!m || typeof m.title !== "string") return null;
      const clamp = (node: Record<string, unknown>, depth: number): { id: string; title: string; children?: unknown[] } => {
        const out: { id: string; title: string; children?: unknown[] } = {
          id: typeof node.id === "string" ? node.id : `n${depth}`,
          title: typeof node.title === "string" ? node.title : "",
        };
        if (depth < 3 && Array.isArray(node.children)) {
          out.children = node.children.filter((c: unknown): c is Record<string, unknown> => !!c && typeof c === "object").slice(0, 12).map((c) => clamp(c, depth + 1));
        } else if (depth < 3) out.children = [];
        return out;
      };
      const root = clamp(m, 0);
      const children = (root.children ?? []) as unknown[];
      if (children.length === 0) return null;
      return { root: { id: root.id, title: root.title, icon: typeof m.icon === "string" ? m.icon : "🧠", children } };
    }
    case "calendarEvents": {
      const events = Array.isArray(raw.calendarEvents) ? raw.calendarEvents : [];
      return events.length ? { events } : null;
    }
    default:
      return null;
  }
}

/** v1 `keywords` was a free string; v2 is string[]. */
export function splitKeywords(raw: unknown): string[] {
  if (Array.isArray(raw)) return raw.filter((k): k is string => typeof k === "string" && k.trim() !== "").slice(0, 20);
  if (typeof raw !== "string") return [];
  return raw.split(/[,;\n]/).map((k) => k.trim()).filter(Boolean).slice(0, 20);
}

/** gs://bucket/path → path ; plain path passes through ; objects (v1 PDF bug) → null. */
export function gcsPath(raw: unknown): string | null {
  if (typeof raw !== "string" || !raw) return null;
  const m = /^gs:\/\/[^/]+\/(.+)$/.exec(raw);
  return m ? m[1] ?? null : raw;
}

// ---------- the migration ----------

export async function migrateUser(db: Firestore, bucket: Bucket, uid: string, opts: MigrateOptions, report: MigrateReport): Promise<void> {
  const log = opts.log ?? noop;
  const userRef = db.doc(`users/${uid}`);
  const userSnap = await userRef.get();
  if (!userSnap.exists) { report.warnings.push(`${uid}: no user doc`); return; }
  const u = userSnap.data() ?? {};
  report.users++;

  // tags: tags/{uid}/tagItems → users/{uid}/tags
  const tagItems = await db.collection(`tags/${uid}/tagItems`).get();
  const tagIds = new Set<string>();
  for (const t of tagItems.docs) {
    const name = typeof t.data().name === "string" ? (t.data().name as string) : t.id;
    tagIds.add(t.id);
    log(`  tag ${t.id} "${name}"`);
    if (!opts.dryRun) {
      await db.doc(`users/${uid}/tags/${t.id}`).set({ name, nameLower: nameKey(name), minuteCount: 0, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp(), migratedAt: FieldValue.serverTimestamp() }, { merge: true });
    }
    report.tags++;
  }

  const minutes = await db.collection(`users/${uid}/minutes`).get();
  const tagCounts = new Map<string, number>();
  for (const m of minutes.docs) {
    const d = m.data();
    if (d.migratedAt && !opts.force) { report.minutesSkipped++; continue; }
    report.minutes++;

    const [trSnap, sumSnap] = await Promise.all([m.ref.collection("metadata").doc("transcription").get(), m.ref.collection("metadata").doc("summary").get()]);
    const transcript = convertV1Transcription(trSnap.data());
    const summary = convertV1Summary(sumSnap.data());
    const ready = transcript !== null;
    const minuteTagIds = (Array.isArray(d.tags) ? d.tags : []).filter((t: unknown): t is string => typeof t === "string" && tagIds.has(t));
    for (const t of minuteTagIds) tagCounts.set(t, (tagCounts.get(t) ?? 0) + 1);
    const sourceType = d.sourceType === "pdf" ? "pdf" : "audio";
    const sourcePath = gcsPath(d.gcsUri) ?? (sourceType === "pdf" ? gcsPath((d.transcriptionUri as { gcsUri?: string } | undefined)?.gcsUri) : null);
    const createdAt = d.createdAt instanceof Timestamp ? d.createdAt : typeof d.createdAt === "string" ? Timestamp.fromDate(new Date(d.createdAt)) : Timestamp.now();
    const tPath = transcriptPath(uid, m.id);

    log(`  minute ${m.id} "${d.title ?? ""}" → ${ready ? "ready" : "failed(no transcript)"} tags=${minuteTagIds.length} source=${sourcePath ?? "none"}`);
    if (ready) report.minutesReady++; else report.minutesFailed++;

    if (!opts.dryRun) {
      if (transcript) {
        await bucket.file(tPath).save(JSON.stringify(transcript), { contentType: "application/json", resumable: false });
        report.transcriptsWritten++;
      }
      await m.ref.set({
        title: typeof d.title === "string" && d.title ? d.title : "Untitled",
        iconEmoji: typeof d.iconAsset === "string" ? d.iconAsset : null,
        sourceType,
        contentKind: typeof d.contentType === "string" ? d.contentType : null,
        status: ready ? "ready" : "failed",
        statusUpdatedAt: FieldValue.serverTimestamp(),
        failure: ready ? null : { code: "migrated_without_transcript", message: "This note from the previous version has no transcript." },
        durationSeconds: transcript?.durationSeconds ?? parseClock(d.duration),
        sourcePath,
        sourceContentType: sourceType === "pdf" ? "application/pdf" : null,
        languageCode: transcript?.languageCode ?? null,
        languageProbability: transcript?.languageProbability ?? null,
        summaryLanguage: typeof d.summaryLanguage === "string" ? d.summaryLanguage : null,
        keywords: splitKeywords(d.keywords),
        description: typeof d.descriptionAudio === "string" ? d.descriptionAudio : null,
        tagIds: minuteTagIds,
        summary,
        transcriptPath: transcript ? tPath : null,
        transcriptPreview: transcript ? previewOf(transcript.text) : null,
        createdAt,
        updatedAt: FieldValue.serverTimestamp(),
        migratedAt: FieldValue.serverTimestamp(),
        v1: { gcsUri: d.gcsUri ?? null, minuteId: d.minuteId ?? null },
      }, { merge: true });
    }

    const sourceHash = transcript ? createHash("sha256").update(transcript.text).digest("hex") : null;
    for (const kind of ["speakers", "shortQuestions", "quiz", "flashcards", "mindmap", "calendarEvents"]) {
      const snap = await m.ref.collection("metadata").doc(kind).get();
      const data = convertV1Artifact(kind, snap.data());
      if (!data) continue;
      log(`    artifact ${kind}`);
      report.artifacts++;
      if (!opts.dryRun) {
        await m.ref.collection("artifacts").doc(kind).set({ kind, data, model: "v1", sourceHash, generatedAt: FieldValue.serverTimestamp(), migratedAt: FieldValue.serverTimestamp() });
      }
    }
  }

  if (!opts.dryRun) {
    for (const [t, n] of tagCounts) await db.doc(`users/${uid}/tags/${t}`).set({ minuteCount: n }, { merge: true });
    await userRef.set({
      photoUrl: typeof u.photoURL === "string" ? u.photoURL : null,
      plan: u.plan === "premium" ? "premium" : "free",
      planExpiresAt: null,
      minuteCount: minutes.size,
      updatedAt: FieldValue.serverTimestamp(),
      migratedAt: FieldValue.serverTimestamp(),
    }, { merge: true });
  }
}

export async function migrateAll(db: Firestore, bucket: Bucket, opts: MigrateOptions, onlyUid?: string): Promise<MigrateReport> {
  const report: MigrateReport = { users: 0, minutes: 0, minutesReady: 0, minutesFailed: 0, minutesSkipped: 0, tags: 0, artifacts: 0, transcriptsWritten: 0, warnings: [] };
  const log = opts.log ?? noop;
  const uids = onlyUid ? [onlyUid] : (await db.collection("users").listDocuments()).map((r) => r.id);
  log(`${opts.dryRun ? "DRY RUN" : "APPLY"} — ${uids.length} user(s)`);
  for (const uid of uids) {
    log(`user ${uid}`);
    try { await migrateUser(db, bucket, uid, opts, report); } catch (err) { report.warnings.push(`${uid}: ${String(err)}`); }
  }
  return report;
}

/** Read-only counts to answer OQ-01. */
export async function inventory(db: Firestore): Promise<Record<string, number>> {
  const users = await db.collection("users").listDocuments();
  let minutes = 0, withTranscript = 0, pdf = 0, youtube = 0, tags = 0, premium = 0;
  for (const u of users) {
    const ud = (await u.get()).data();
    if (ud?.plan === "premium") premium++;
    const ms = await u.collection("minutes").get();
    minutes += ms.size;
    for (const m of ms.docs) {
      if (m.data().sourceType === "pdf") pdf++;
      if (m.data().sourceType === "youtube") youtube++;
      if ((await m.ref.collection("metadata").doc("transcription").get()).exists) withTranscript++;
    }
    tags += (await db.collection(`tags/${u.id}/tagItems`).count().get()).data().count;
  }
  return { users: users.length, premiumUsers: premium, minutes, minutesWithTranscript: withTranscript, minutesPdf: pdf, minutesYoutube: youtube, tags };
}

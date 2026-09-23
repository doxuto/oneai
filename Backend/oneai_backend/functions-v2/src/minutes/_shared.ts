import { HttpsError } from "firebase-functions/v2/https";
import type { DocumentData, DocumentReference, DocumentSnapshot, Firestore, Timestamp } from "firebase-admin/firestore";
import { toIso } from "../lib/time.js";
import {
  ARTIFACT_KINDS,
  MinuteStatus,
  SourceType,
  type ArtifactKind,
  type CalendarEvent,
  type MinuteDetail,
  type MinuteSummary,
  type Speaker,
  type Summary,
  type TalkTime,
  type Transcript,
} from "./types.js";

/** `users/{uid}/minutes/{minuteId}` on disk. Every field optional — be tolerant. */
export interface MinuteDoc {
  title?: string;
  iconEmoji?: string | null;
  sourceType?: string;
  contentKind?: string | null;
  status?: string;
  statusUpdatedAt?: Timestamp;
  failure?: { code?: string; message?: string } | null;
  durationSeconds?: number | null;
  sourcePath?: string | null;
  /** "available" while the bytes exist; "expired" once retention removed them. */
  sourceState?: string | null;
  sourceExpiresAt?: Timestamp | null;
  sourceContentType?: string | null;
  sourceSizeBytes?: number | null;
  languageCode?: string | null;
  languageProbability?: number | null;
  /** Vendor/model that produced the transcript. */
  stt?: { vendor?: string; model?: string } | null;
  timezone?: string | null;
  summaryLanguage?: string | null;
  keywords?: string[];
  description?: string | null;
  tagIds?: string[];
  summary?: Summary | null;
  transcriptPath?: string | null;
  transcriptPreview?: string | null;
  createdAt?: Timestamp;
  updatedAt?: Timestamp;
}

// ---------- paths ----------

export const minutesCol = (db: Firestore, uid: string) => db.collection(`users/${uid}/minutes`);
export const minuteRef = (db: Firestore, uid: string, id: string): DocumentReference =>
  db.doc(`users/${uid}/minutes/${id}`);
export const tagsCol = (db: Firestore, uid: string) => db.collection(`users/${uid}/tags`);

/** Storage prefix for everything a minute owns. Matches storage.rules. */
export const minutePrefix = (uid: string, id: string) => `users/${uid}/minutes/${id}/`;
export const sourcePath = (uid: string, id: string, fileName: string) =>
  `${minutePrefix(uid, id)}source/${fileName}`;
export const transcriptPath = (uid: string, id: string) => `${minutePrefix(uid, id)}transcript.json`;

// ---------- ownership ----------

/**
 * Ownership lives in the path, so a caller can only ever address their own
 * subtree. Missing ⇒ not-found (never reveal whether someone else has it).
 */
export async function loadOwnedMinute(
  db: Firestore,
  uid: string,
  id: string,
): Promise<{ ref: DocumentReference; snap: DocumentSnapshot; doc: MinuteDoc }> {
  const ref = minuteRef(db, uid, id);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError("not-found", "Note not found");
  return { ref, snap, doc: (snap.data() ?? {}) as MinuteDoc };
}

// ---------- file name hygiene ----------

/** Keep the basename, drop anything that could escape the prefix. */
export function safeFileName(name: string): string {
  const base = name.split(/[\\/]/).pop() ?? "";
  const cleaned = base.replace(/[^A-Za-z0-9._ -]/g, "_").replace(/^\.+/, "").trim();
  return (cleaned || "file").slice(0, 120);
}

/** Content type must agree with the declared source type. */
export function contentTypeMatches(sourceType: SourceType, contentType: string): boolean {
  const ct = contentType.toLowerCase();
  if (sourceType === "audio") return ct.startsWith("audio/") || ct === "video/mp4" || ct === "video/quicktime";
  if (sourceType === "pdf") return ct === "application/pdf";
  return false;
}

// ---------- mappers (explicit; never return snap.data()) ----------

function str(v: unknown): string | null {
  return typeof v === "string" ? v : null;
}
function num(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}
function strList(v: unknown): string[] {
  return Array.isArray(v) ? v.filter((x): x is string => typeof x === "string") : [];
}

export function toMinuteSummary(id: string, raw: DocumentData | undefined): MinuteSummary {
  const d = (raw ?? {}) as MinuteDoc;
  const statusParsed = MinuteStatus.safeParse(d.status);
  const sourceParsed = SourceType.safeParse(d.sourceType);
  return {
    id,
    title: str(d.title) ?? "Untitled",
    iconEmoji: str(d.iconEmoji),
    sourceType: sourceParsed.success ? sourceParsed.data : "audio",
    contentKind: str(d.contentKind),
    status: statusParsed.success ? statusParsed.data : "failed",
    durationSeconds: num(d.durationSeconds),
    tagIds: strList(d.tagIds),
    createdAt: toIso(d.createdAt ?? null) ?? "1970-01-01T00:00:00.000Z",
    updatedAt: toIso(d.updatedAt ?? d.createdAt ?? null) ?? "1970-01-01T00:00:00.000Z",
  };
}

export function toSummary(raw: unknown): Summary | null {
  if (!raw || typeof raw !== "object") return null;
  const s = raw as Record<string, unknown>;
  const sections = Array.isArray(s.sections)
    ? s.sections
        .filter((x): x is Record<string, unknown> => !!x && typeof x === "object")
        .map((x) => ({ title: str(x.title) ?? "", bullets: strList(x.bullets) }))
    : [];
  return {
    title: str(s.title) ?? "",
    text: str(s.text) ?? "",
    icon: str(s.icon),
    sections,
  };
}

export function toTranscript(raw: unknown): Transcript | null {
  if (!raw || typeof raw !== "object") return null;
  const t = raw as Record<string, unknown>;
  const segments = Array.isArray(t.segments)
    ? t.segments
        .filter((x): x is Record<string, unknown> => !!x && typeof x === "object")
        .map((x) => ({
          startSeconds: num(x.startSeconds) ?? 0,
          endSeconds: num(x.endSeconds) ?? 0,
          text: str(x.text) ?? "",
          speakerId: str(x.speakerId) ?? "speaker_0",
          speakerLabel: str(x.speakerLabel) ?? "Speaker 1",
        }))
    : [];
  return {
    durationSeconds: num(t.durationSeconds) ?? 0,
    languageCode: str(t.languageCode),
    languageProbability: num(t.languageProbability),
    text: str(t.text) ?? "",
    segments,
  };
}

export function toSpeakers(raw: unknown): Speaker[] {
  if (!raw || typeof raw !== "object") return [];
  const d = raw as Record<string, unknown>;
  const list = d.speakers;
  if (!Array.isArray(list)) return [];
  return list
    .filter((x): x is Record<string, unknown> => !!x && typeof x === "object")
    .map((x) => ({ id: str(x.id) ?? "", label: str(x.label) ?? "" }))
    .filter((s) => s.id !== "");
}

export function toCalendarEvents(raw: unknown): CalendarEvent[] {
  if (!raw || typeof raw !== "object") return [];
  const list = (raw as Record<string, unknown>).events;
  if (!Array.isArray(list)) return [];
  return list
    .filter((x): x is Record<string, unknown> => !!x && typeof x === "object")
    .map((x, i) => ({
      id: str(x.id) ?? `ev_${i}`,
      title: str(x.title) ?? "",
      description: str(x.description) ?? "",
      datetime: str(x.datetime) ?? "",
      participants: strList(x.participants),
      rawText: str(x.rawText) ?? "",
    }))
    .filter((e) => e.title !== "" || e.datetime !== "");
}

/** The artifact kinds present among a minute's `artifacts/` docs, in canonical order. */
export function presentArtifactKinds(ids: Iterable<string>): ArtifactKind[] {
  const set = new Set(ids);
  return ARTIFACT_KINDS.filter((k) => set.has(k));
}

/** Who spoke how much. Pure over the transcript; a PDF (single "document" segment) yields []. */
export function talkTimeOf(transcript: Transcript | null, speakers: Speaker[]): TalkTime[] {
  if (!transcript || transcript.segments.length === 0) return [];
  if (transcript.segments.every((s) => s.speakerId === "document")) return [];
  const acc = new Map<string, { seconds: number; turns: number; label: string }>();
  for (const seg of transcript.segments) {
    const cur = acc.get(seg.speakerId) ?? { seconds: 0, turns: 0, label: seg.speakerLabel };
    cur.seconds += Math.max(0, seg.endSeconds - seg.startSeconds);
    cur.turns += 1;
    acc.set(seg.speakerId, cur);
  }
  const total = [...acc.values()].reduce((t, v) => t + v.seconds, 0);
  const labelOf = (id: string, fallback: string) => speakers.find((s) => s.id === id)?.label ?? fallback;
  return [...acc.entries()]
    .map(([speakerId, v]) => ({
      speakerId,
      label: labelOf(speakerId, v.label),
      seconds: Math.round(v.seconds * 10) / 10,
      share: total > 0 ? Math.round((v.seconds / total) * 1000) / 1000 : 0,
      turns: v.turns,
    }))
    .sort((a, b) => b.seconds - a.seconds);
}

export function toMinuteDetail(
  id: string,
  raw: DocumentData | undefined,
  extras: { transcript: Transcript | null; speakers: Speaker[]; calendarEvents?: CalendarEvent[]; availableArtifacts?: ArtifactKind[] },
): MinuteDetail {
  const d = (raw ?? {}) as MinuteDoc;
  return {
    ...toMinuteSummary(id, raw),
    summary: toSummary(d.summary),
    transcript: extras.transcript,
    sourcePath: str(d.sourcePath),
    sourceState: d.sourceState === "expired" ? "expired" : d.sourcePath ? "available" : "none",
    sourceExpiresAt: toIso(d.sourceExpiresAt ?? null),
    speakers: extras.speakers,
    failure:
      d.failure && typeof d.failure === "object"
        ? { code: str(d.failure.code) ?? "unknown", message: str(d.failure.message) ?? "" }
        : null,
    description: str(d.description),
    keywords: strList(d.keywords),
    summaryLanguage: str(d.summaryLanguage),
    calendarEvents: extras.calendarEvents ?? [],
    availableArtifacts: extras.availableArtifacts ?? [],
    talkTime: talkTimeOf(extras.transcript, extras.speakers),
  };
}

import type { DocumentData, Timestamp } from "firebase-admin/firestore";
import { toIso } from "../lib/time.js";
import type { TagOutput } from "./types.js";

export interface TagDoc {
  name?: string;
  nameLower?: string;
  minuteCount?: number;
  createdAt?: Timestamp;
  updatedAt?: Timestamp;
}

/** Uniqueness key. Collapses case and inner whitespace: "Team  Sync" == "team sync". */
export function nameKey(name: string): string {
  return name.trim().toLowerCase().replace(/\s+/g, " ");
}

export function toTagOutput(id: string, raw: DocumentData | undefined): TagOutput {
  const d = (raw ?? {}) as TagDoc;
  return {
    id,
    name: typeof d.name === "string" ? d.name : "",
    minuteCount: typeof d.minuteCount === "number" ? d.minuteCount : 0,
    createdAt: toIso(d.createdAt ?? null) ?? "1970-01-01T00:00:00.000Z",
  };
}

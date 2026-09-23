import { z } from "zod";
import { DocId, withClient } from "../types/common.js";

export const CreateShareLinkInput = withClient({
  minuteId: DocId,
  /** Include the transcript on the page (default: summary only). */
  includeTranscript: z.boolean().default(false),
}).strict();
export type CreateShareLinkInput = z.infer<typeof CreateShareLinkInput>;

export const RevokeShareLinkInput = withClient({ minuteId: DocId }).strict();

export interface ShareInfo {
  url: string;
  includeTranscript: boolean;
  createdAt: string;
  views: number;
}
export interface CreateShareLinkOutput { share: ShareInfo }
export type RevokeShareLinkOutput = Record<string, never>;

/** `shares/{token}` on disk. Top-level so the public page needs no uid. */
export interface ShareDoc {
  uid: string;
  minuteId: string;
  includeTranscript: boolean;
  createdAt: FirebaseFirestore.Timestamp;
  revokedAt: FirebaseFirestore.Timestamp | null;
  views: number;
}

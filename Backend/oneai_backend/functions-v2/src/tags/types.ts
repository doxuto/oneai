import { z } from "zod";
import { DocId, withClient } from "../types/common.js";

export const MAX_TAG_NAME = 40;
export const TagName = z.string().trim().min(1).max(MAX_TAG_NAME);

export const CreateTagInput = withClient({ name: TagName }).strict();
export const ListTagsInput = withClient({});
export const UpdateTagInput = withClient({ tagId: DocId, name: TagName }).strict();
export const DeleteTagInput = withClient({ tagId: DocId }).strict();

export interface TagOutput {
  id: string;
  name: string;
  minuteCount: number;
  createdAt: string;
}

export interface CreateTagOutput { tag: TagOutput }
export interface ListTagsOutput { items: TagOutput[] }
export interface UpdateTagOutput { tag: TagOutput }
export interface DeleteTagOutput { affectedMinuteCount: number }

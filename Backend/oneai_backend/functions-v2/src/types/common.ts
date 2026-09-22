import { z } from "zod";

/**
 * Every request carries a client block. firebase-ios-contract/versioning:
 * the min-version gate is the only force-update mechanism the skills allow.
 */
export const ClientInfoSchema = z.object({
  appVersion: z.string().min(1).max(20),
  build: z.number().int().min(0).max(1_000_000),
  platform: z.enum(["ios", "android"]),
});
export type ClientInfo = z.infer<typeof ClientInfoSchema>;

/** Mix into every input schema. */
export const withClient = <T extends z.ZodRawShape>(shape: T) =>
  z.object({ client: ClientInfoSchema, ...shape });

/** Bounded primitives — unbounded input is a cost and abuse vector. */
export const DocId = z.string().min(1).max(128).regex(/^[^/]+$/, "must not contain '/'");
export const ShortText = z.string().max(200);
export const LongText = z.string().max(2000);
export const LanguageCode = z.string().min(2).max(35);
export const Cursor = z.string().max(512);

/** Timestamps cross the wire as ISO-8601 with fractional seconds and Z. */
export type IsoDateTime = string;

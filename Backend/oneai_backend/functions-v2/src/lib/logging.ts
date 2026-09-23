/**
 * Structured logging. firebase-functions-pro/errors-and-logging:
 *   - first arg is a stable event name `domain.thing.event`
 *   - second arg is a flat object, depth <= 2
 *   - `uid` on every user-scoped log
 *   - NEVER: email, display name, prompt text, note contents, tokens, secrets
 */
import { logger } from "firebase-functions/v2";

export type LogFields = Record<string, string | number | boolean | null | undefined>;

export const log = {
  debug: (event: string, fields?: LogFields) => logger.debug(event, fields),
  info: (event: string, fields?: LogFields) => logger.info(event, fields),
  warn: (event: string, fields?: LogFields) => logger.warn(event, fields),
  /** Reserve for real bugs. Expected client mistakes floods Error Reporting. */
  error: (event: string, fields?: LogFields) => logger.error(event, fields),
};

/** Log one line at the end of a request with its duration. */
export function logDone(event: string, startedAt: number, fields?: LogFields): void {
  log.info(event, { ...fields, ms: Date.now() - startedAt });
}

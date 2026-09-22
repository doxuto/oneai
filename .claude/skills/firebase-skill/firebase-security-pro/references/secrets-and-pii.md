# Secrets, params, logging, and PII

Targets firebase-functions 6.x (`firebase-functions/params`, `firebase-functions/logger`), firebase-admin 13.x, Google Cloud Secret Manager.

## Secrets vs params

| | `defineSecret` | `defineString` / `defineInt` / `defineBoolean` |
|---|---|---|
| Stored in | Cloud Secret Manager (encrypted, versioned, IAM-gated) | `.env`, `.env.<projectId>`, `.env.local` in the functions dir (plain text, committed) |
| For | API keys, signing keys, webhook secrets, DB passwords | region names, feature flags, bucket names, public IDs (Sentry DSN, RevenueCat public key) |
| Read | `SECRET.value()` inside a handler, only in functions that declare `secrets: [SECRET]` | `PARAM.value()` inside a handler |
| Set | `firebase functions:secrets:set NAME` (prompts; or `--data-file`) | edit the `.env` file |
| Per environment | one Secret Manager secret per project (`snaptool-dev`, `snaptool-prod`) | `.env.snaptool-prod` overrides `.env` |

```ts
import { defineSecret, defineString } from "firebase-functions/params";
import { onCall } from "firebase-functions/v2/https";

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
const REVENUECAT_WEBHOOK_SECRET = defineSecret("REVENUECAT_WEBHOOK_SECRET");
const SENTRY_DSN = defineString("SENTRY_DSN");                  // public, fine in .env

export const summarize = onCall({ secrets: [GEMINI_API_KEY], enforceAppCheck: true }, async (request) => {
  const key = GEMINI_API_KEY.value();                           // inside the handler only
  // ...
});
```

Rules:

- `SECRET.value()` at module top level is **empty at deploy-time analysis** and throws or yields `""` — the CLI loads the module to discover exports without secret access. Build the SDK client lazily inside the handler or in a memoised function called from the handler.
- A function that does not list a secret in `secrets: [...]` cannot read it, even if it is in the same codebase. This is a feature: the blast radius of a bug in `sendPush` does not include the Gemini key.
- `functions.config()` is deprecated and removed for new deployments (March 2026). Any `functions.config().x.y` is a finding.
- Never commit `.env.local` or `.env.*` files that contain secrets. `.env` files are for non-secret config only; if a value would be a problem on GitHub, it is a secret.
- Secrets are not available to the iOS app at all. If a value must reach the client (public Maps key, RevenueCat public SDK key) it is by definition not a secret; put it in the app bundle or serve it via Remote Config, and restrict it by bundle ID in the provider's console.

## Rotation

1. `firebase functions:secrets:set GEMINI_API_KEY` creates a **new version**; running functions keep the version they were deployed with.
2. `firebase deploy --only functions` (or the functions that declare the secret) picks up the latest version.
3. Once no function references the old version, `firebase functions:secrets:prune` destroys unused versions; `firebase functions:secrets:destroy GEMINI_API_KEY@1` for a specific one. `firebase functions:secrets:access GEMINI_API_KEY` prints the current value (only for debugging on a trusted machine).
4. Rotate immediately on: a leaked log line, a departed team member with `secretmanager.versions.access`, a provider notice. Rotate routinely every 90 days for third-party API keys.

Webhook secrets (RevenueCat, Stripe, Apple Server Notifications): verify signature or bearer with a constant-time compare, and support two active secrets during rotation:

```ts
import { timingSafeEqual } from "node:crypto";
function bearerMatches(header: string | undefined, ...allowed: string[]): boolean {
  if (!header?.startsWith("Bearer ")) return false;
  const got = Buffer.from(header.slice(7));
  return allowed.some((s) => { const exp = Buffer.from(s); return exp.length === got.length && timingSafeEqual(exp, got); });
}
```

## Logging

Use the structured logger; never `console.log` an object (it becomes a flat string and loses severity).

```ts
import { logger } from "firebase-functions/logger";
logger.info("ocr done", { uid, scanId, pages: 3, ms: 812, tokens: usage.totalTokenCount });
logger.warn("quota exceeded", { uid, key: "ocr" });
logger.error("gemini failed", { uid, scanId, code: err.code, err: String(err) });
```

Never log:

- ID tokens, App Check tokens, `Authorization` headers, session cookies, custom tokens, signed URLs, download-token URLs.
- API keys or secret values, including inside error messages from providers (`Invalid API key: AIza…` — truncate provider errors to their `code`).
- Email addresses, phone numbers, full names, device identifiers beyond your own installation id, IP addresses in application logs (Cloud Run request logs already have them).
- Full request bodies or document bodies containing user content (note text, OCR output, images as base64).
- Stack traces that include user data in messages.

Log instead: `uid`, document ids, counts, durations, error codes, model name, token usage. `uid` is a pseudonymous identifier and acceptable in logs under GDPR as long as logs have a retention limit (Cloud Logging default 30 days; set a bucket retention policy explicitly).

### Redacting logger wrapper

```ts
// functions/src/lib/log.ts
import { logger } from "firebase-functions/logger";

const SENSITIVE_KEYS = new Set(["authorization", "idtoken", "token", "apikey", "api_key", "secret", "password",
  "email", "phone", "phonenumber", "displayname", "body", "ocrtext", "text", "base64", "url"]);
const EMAIL_RE = /[\w.+-]+@[\w-]+\.[\w.]+/g;
const BEARER_RE = /Bearer\s+[A-Za-z0-9._-]+/g;

export function redact(value: unknown, depth = 0): unknown {
  if (depth > 4) return "[depth]";
  if (typeof value === "string") {
    return value.replace(BEARER_RE, "Bearer [redacted]").replace(EMAIL_RE, "[email]").slice(0, 500);
  }
  if (Array.isArray(value)) return value.slice(0, 20).map((v) => redact(v, depth + 1));
  if (value && typeof value === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      out[k] = SENSITIVE_KEYS.has(k.toLowerCase()) ? "[redacted]" : redact(v, depth + 1);
    }
    return out;
  }
  return value;
}

export const log = {
  info: (msg: string, fields?: Record<string, unknown>) => logger.info(msg, redact(fields)),
  warn: (msg: string, fields?: Record<string, unknown>) => logger.warn(msg, redact(fields)),
  error: (msg: string, fields?: Record<string, unknown>) => logger.error(msg, redact(fields)),
  debug: (msg: string, fields?: Record<string, unknown>) => logger.debug(msg, redact(fields)),
};
```

Use `log.*` everywhere instead of `logger.*`; review any direct `logger` import in a diff. Errors thrown from a handler are recorded in Error Reporting with their message — keep `HttpsError` messages free of user data too.

## Data minimisation

- Collect what the feature needs. Do not store Apple `fullName` components you never display; do not store the relay email if you never email users.
- Prefer the uid over email as the join key everywhere (Firestore docs, Storage paths, external customer ids).
- Store dates of birth as age brackets if that is all you use; store coarse location if you never need exact.
- OCR text and extracted fields from scans are user content with potentially high sensitivity (IDs, invoices). Keep them under `users/{uid}/…` only, never in a top-level collection, never in analytics events, never in prompts sent to a model without the user having initiated that action.
- Model providers: with the Gemini Developer API, check the current data-use terms for your tier; with Vertex AI, data is not used for training by default. Do not send more of a document than the feature needs (crop, downscale, truncate).
- Analytics: never set `email` or a name as a user property; `setUserID` with the Firebase uid or a hashed id only.

## Retention

- Firestore TTL policy on transient collections (`_ratelimit`, `events` ledger, exports) — `expiresAt` Timestamp field + TTL policy in console/gcloud; deletion within ~24 h of expiry.
- Cloud Logging: set retention on the `_Default` bucket (e.g. 30 days) — `gcloud logging buckets update _Default --location=global --retention-days=30`.
- Storage lifecycle rules on export/backup buckets (delete after N days) via the GCS console or `gsutil lifecycle set`.
- Anonymous users: auto-cleanup + scheduled data deletion after 30 days.

## GDPR-style export and delete

Even if the user base is in Vietnam (PDPD, Decree 13/2023) the shape is the same as GDPR/CCPA: the user can request a copy and request deletion, in-app, without support.

- **Export** — `exportAccount` callable: recent-sign-in check, gather `users/{uid}` subtree with `recursive` reads (paginate subcollections), top-level docs keyed by uid, Storage object list (paths, not bytes, unless small), serialise to JSON with Timestamps as ISO strings, write to a private `exports` bucket at `exports/{uid}/{exportId}.json`, return a 15-minute signed URL. Set a lifecycle rule to delete exports after 7 days. Log the request (uid, exportId).
- **Delete** — the `deleteAccount` callable in `sign-in-with-apple-and-deletion.md`; ensure it also reaches external processors (RevenueCat `DELETE /subscribers/{id}`, Stripe customer delete, analytics deletion API) and that backups/exports are excluded from the guarantee in your privacy policy or purged on schedule.
- **Rectify** — the user edits their own profile via rules-allowed fields; nothing special.
- Keep a `privacy/{uid}` audit doc with `exportedAt`, `deletionRequestedAt`, `deletedAt` written by the server only, so support can answer "did we delete it".

## Third-party processors

Document each: provider, purpose, data sent, region, retention. Typical list for this bundle: Firebase/GCP (Singapore), Google Gemini or Vertex AI (model calls: document images and text), APNs (push token + payload), RevenueCat (app user id, receipts). This list is what the App Store privacy "nutrition label" and the in-app privacy policy must match — review `PrivacyInfo.xcprivacy` on the iOS side when the list changes.

## Does not exist / common mistakes

- `functions.config()` — deprecated/removed. Params and secrets only.
- `process.env.GEMINI_API_KEY` for a secret without `defineSecret` + `secrets: [...]` — it is undefined at runtime (unless someone pasted it into `.env`, which is the finding).
- `defineSecret(...).value()` at module scope — empty during deploy analysis; call inside the handler.
- Logging `request.data` wholesale "for debugging" — user content and possibly credentials in Cloud Logging for 30 days.
- Returning provider error messages to the client (`throw new HttpsError("internal", err.message)`) — leaks internals; return a fixed message, log the detail.
- Storing an API key in Remote Config or Firestore "so the app can use it" — the app is not a trusted environment; move the call server-side or restrict the key by bundle ID at the provider.
- `console.error(err)` with an axios/fetch error object — the request config (including `Authorization` headers) is serialised into the log.

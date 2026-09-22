# HTTP functions (`onRequest`)

Use `onRequest` for endpoints the Firebase client SDK does not call: webhooks from RevenueCat, App Store Server Notifications, Stripe, health checks, and the rare browser-facing endpoint. Everything the iOS app calls directly should be `onCall` — you get auth, App Check, and error mapping for free.

## Anatomy

```ts
import { onRequest, type Request } from "firebase-functions/v2/https";
import type { Response } from "express";

export const health = onRequest(
  {
    cors: false,          // boolean | string | RegExp | Array<string | RegExp>
    invoker: "public",    // "public" | "private" | string[] of service accounts / principals
    memory: "128MiB",
    timeoutSeconds: 10,
  },
  async (req: Request, res: Response) => {
    if (req.method !== "GET") {
      res.status(405).set("Allow", "GET").send("Method Not Allowed");
      return;
    }
    res.status(200).json({ ok: true, time: new Date().toISOString() });
  },
);
```

- `req` is an express `Request` with `req.rawBody: Buffer` added (needed for signature verification). `req.body` is parsed JSON when `Content-Type: application/json`.
- Always `return` after sending, or the handler falls through to the next branch and double-sends (`ERR_HTTP_HEADERS_SENT`, logged as `internal`).
- The handler may be `async`; the platform waits for the returned promise. Do not leave promises dangling after `res.send()`.
- `timeoutSeconds` for HTTP functions can go up to 3600 in v2; callables and event functions cap at 540. Long webhooks should still enqueue and return 200 fast.

## `cors`

| Value | Meaning |
|---|---|
| `false` / omitted | No CORS headers; browsers block cross-origin calls. Correct for webhooks. |
| `true` | `Access-Control-Allow-Origin: *`. Only for public read-only data. |
| `["https://app.example.com", /\.example\.com$/]` | Allowlist. Use this for anything a web front end calls. |

CORS is a browser concept; the iOS app and webhook senders ignore it. Do not set `cors: true` to "fix" an iOS or curl failure — that failure is something else (invoker, auth, App Check).

## `invoker`

- `"public"` — anyone with the URL can hit it. Required for webhooks and anything the app calls without a Google identity.
- `"private"` — only principals with `roles/run.invoker` on the underlying Cloud Run service. Use for functions called from Cloud Scheduler with OIDC, from other functions with an identity token, or from Cloud Tasks.
- `["serviceAccount:x@project.iam.gserviceaccount.com"]` — explicit principals.

Default is `"public"`. A 403 with an HTML body from `run.app` means the invoker check failed, not your code.

## Express app inside one function

For a small REST surface, mount an express app once at module level:

```ts
import express from "express";
import { onRequest } from "firebase-functions/v2/https";

const app = express();
app.use(express.json({ limit: "1mb" }));

app.get("/v1/plans", async (_req, res) => {
  res.json({ plans: ["free", "pro"] });
});

export const api = onRequest({ cors: ["https://app.example.com"], invoker: "public" }, app);
```

One function per express app means one set of runtime options, one log stream, and one cold start for the whole surface. That is acceptable for a handful of routes; split when a route needs different memory, secrets, or timeout. Deployed URL is `https://api-<hash>-<region>.a.run.app` plus the route, or the `cloudfunctions.net` alias.

## Verifying the caller manually

A callable does this for you. In `onRequest` you own it.

### Firebase ID token

```ts
import { getAuth } from "firebase-admin/auth";
import { HttpsError } from "firebase-functions/v2/https";

async function requireUser(req: Request): Promise<string> {
  const header = req.get("Authorization") ?? "";
  const match = /^Bearer (.+)$/.exec(header);
  if (!match) throw new HttpsError("unauthenticated", "Missing bearer token");
  try {
    const decoded = await getAuth().verifyIdToken(match[1], /* checkRevoked */ true);
    return decoded.uid;
  } catch {
    throw new HttpsError("unauthenticated", "Invalid token");
  }
}
```

`checkRevoked: true` costs one Auth lookup per call; use it on sensitive endpoints only.

### App Check token

```ts
import { getAppCheck } from "firebase-admin/app-check";

async function requireAppCheck(req: Request, consume = false): Promise<void> {
  const token = req.get("X-Firebase-AppCheck");
  if (!token) throw new HttpsError("unauthenticated", "Missing App Check token");
  try {
    const result = await getAppCheck().verifyToken(token, { consume });
    if (consume && result.alreadyConsumed) {
      throw new HttpsError("permission-denied", "Replayed App Check token");
    }
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    throw new HttpsError("unauthenticated", "Invalid App Check token");
  }
}
```

Translate `HttpsError` into an HTTP status yourself in `onRequest` — the SDK does not do it for you here:

```ts
const STATUS: Record<string, number> = {
  "invalid-argument": 400, unauthenticated: 401, "permission-denied": 403,
  "not-found": 404, "already-exists": 409, "failed-precondition": 412,
  "resource-exhausted": 429, unavailable: 503, internal: 500,
};

function sendError(res: Response, err: unknown): void {
  if (err instanceof HttpsError) {
    res.status(STATUS[err.code] ?? 500).json({ error: { code: err.code, message: err.message, details: err.details ?? null } });
    return;
  }
  logger.error("http.unhandled", { error: String(err) });
  res.status(500).json({ error: { code: "internal", message: "Internal error" } });
}
```

## Webhooks

Pattern for every webhook: verify → dedupe → enqueue or write → respond 200 quickly. Never do the real work inline; a slow handler makes the sender retry and you double-process.

### RevenueCat

RevenueCat signs nothing by default; it sends the `Authorization` header value you configured in the dashboard. Compare it in constant time.

```ts
import { timingSafeEqual } from "node:crypto";
import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions/logger";
import { z } from "zod";
import { db } from "../lib/admin.js";

const REVENUECAT_WEBHOOK_TOKEN = defineSecret("REVENUECAT_WEBHOOK_TOKEN");

const Event = z.object({
  api_version: z.string(),
  event: z.object({
    id: z.string(),
    type: z.string(),                 // INITIAL_PURCHASE, RENEWAL, CANCELLATION, EXPIRATION, ...
    app_user_id: z.string(),          // = Firebase uid if you set it on the client
    product_id: z.string().optional(),
    entitlement_ids: z.array(z.string()).nullable().optional(),
    expiration_at_ms: z.number().nullable().optional(),
    event_timestamp_ms: z.number(),
  }),
});

function safeEqual(a: string, b: string): boolean {
  const ab = Buffer.from(a), bb = Buffer.from(b);
  return ab.length === bb.length && timingSafeEqual(ab, bb);
}

export const revenueCatWebhook = onRequest(
  { invoker: "public", secrets: [REVENUECAT_WEBHOOK_TOKEN], timeoutSeconds: 30, memory: "256MiB" },
  async (req, res) => {
    if (req.method !== "POST") { res.status(405).send(""); return; }
    if (!safeEqual(req.get("Authorization") ?? "", REVENUECAT_WEBHOOK_TOKEN.value())) {
      res.status(401).send(""); return;
    }
    const parsed = Event.safeParse(req.body);
    if (!parsed.success) { res.status(400).send(""); return; }
    const { event } = parsed.data;

    // Idempotency: create() fails with ALREADY_EXISTS (code 6) if this event was seen.
    try {
      await db.doc(`webhookEvents/rc_${event.id}`).create({ type: event.type, receivedAt: new Date() });
    } catch (err) {
      if ((err as { code?: number }).code === 6) { res.status(200).send("duplicate"); return; }
      throw err;
    }

    await db.doc(`users/${event.app_user_id}`).set(
      {
        entitlements: event.entitlement_ids ?? [],
        entitlementExpiresAt: event.expiration_at_ms ? new Date(event.expiration_at_ms) : null,
        entitlementSource: "revenuecat",
      },
      { merge: true },
    );
    logger.info("revenuecat.event", { type: event.type, uid: event.app_user_id });
    res.status(200).send("ok");
  },
);
```

Verify the current event schema against RevenueCat docs; field names above are the stable core but the payload has grown over time. Return 200 for events you deliberately ignore; anything else triggers retries.

### App Store Server Notifications V2

Apple posts `{ "signedPayload": "<JWS>" }`. Verify the JWS chain with Apple's library rather than decoding the JWT by hand.

```ts
import { SignedDataVerifier, Environment } from "@apple/app-store-server-library";
import { readFileSync } from "node:fs";

// Apple root certs (DER) bundled with the deploy; download from Apple PKI.
const APPLE_ROOTS = ["AppleRootCA-G3.cer", "AppleRootCA-G2.cer"].map((f) => readFileSync(new URL(`../certs/${f}`, import.meta.url)));

let verifier: SignedDataVerifier | undefined;
function getVerifier(): SignedDataVerifier {
  verifier ??= new SignedDataVerifier(APPLE_ROOTS, /* enableOnlineChecks */ true, Environment.PRODUCTION, "com.example.snaptool", /* appAppleId */ 123456789);
  return verifier;
}

export const appStoreNotifications = onRequest({ invoker: "public", timeoutSeconds: 30 }, async (req, res) => {
  if (req.method !== "POST") { res.status(405).send(""); return; }
  const signedPayload = (req.body as { signedPayload?: string })?.signedPayload;
  if (!signedPayload) { res.status(400).send(""); return; }
  try {
    const payload = await getVerifier().verifyAndDecodeNotification(signedPayload);
    // payload.notificationType, payload.subtype, payload.data?.signedTransactionInfo (verify again with verifyAndDecodeTransaction)
    logger.info("appstore.notification", { type: payload.notificationType, subtype: payload.subtype });
    // dedupe on payload.notificationUUID, then enqueue or write status
    res.status(200).send("");
  } catch (err) {
    logger.warn("appstore.notification.invalid", { error: String(err) });
    res.status(401).send("");
  }
});
```

Use a separate function (or `Environment.SANDBOX`) for the sandbox URL you register in App Store Connect. Verify the constructor arguments against the current `@apple/app-store-server-library` README — the argument order has changed between releases.

### Generic HMAC (Stripe-style)

```ts
import { createHmac, timingSafeEqual } from "node:crypto";

function verifyHmac(rawBody: Buffer, header: string, secret: string): boolean {
  const expected = createHmac("sha256", secret).update(rawBody).digest("hex");
  const got = Buffer.from(header, "utf8"), exp = Buffer.from(expected, "utf8");
  return got.length === exp.length && timingSafeEqual(got, exp);
}
// use req.rawBody — never JSON.stringify(req.body), key order changes the digest
```

## Does not exist / common mistakes

- `functions.https.onRequest` (v1) with a v2 options object — pick one API.
- `onRequest` without `invoker` for a webhook while the project's org policy defaults to private — the sender gets 403. Set `invoker: "public"` explicitly.
- Forgetting `return` after `res.send()` — double response, logged as `internal`.
- Comparing secrets with `===` — timing side channel. Use `timingSafeEqual` on equal-length buffers.
- Verifying an HMAC over `JSON.stringify(req.body)` — use `req.rawBody`.
- Doing the real work in the webhook handler — enqueue with `getFunctions().taskQueue(...)` and return 200.
- Throwing `HttpsError` inside `onRequest` and expecting a JSON error response — the SDK does not translate it there; catch and map to a status yourself.
- Using `cors: true` on a webhook — harmless but signals the author did not know what CORS is for; drop it.

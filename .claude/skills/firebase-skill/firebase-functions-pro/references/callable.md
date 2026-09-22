# Callable functions (`onCall`)

A callable is the default way the iOS app talks to the server: the Firebase SDK attaches the ID token, App Check token, and FCM instance token automatically, serialises the payload as JSON, and maps `HttpsError` to `FunctionsErrorCode` on the client. Use `onRequest` only for webhooks and third-party integrations.

## Anatomy

```ts
import { onCall, HttpsError, type CallableRequest, type CallableOptions } from "firebase-functions/v2/https";

export const name = onCall(
  options,                                   // CallableOptions — optional, but always pass enforceAppCheck
  async (request: CallableRequest<T>) => {   // one argument; (request, response) for streaming
    // 1. authenticate
    // 2. validate request.data
    // 3. authorise (does this uid own this resource?)
    // 4. do work
    // 5. return a JSON-serialisable object
  },
);
```

Options that matter for callables (`CallableOptions extends GlobalOptions`):

| Option | Notes |
|---|---|
| `enforceAppCheck: true` | Reject requests without a valid App Check token. Set it on everything the app calls. |
| `consumeAppCheckToken: true` | Token is single-use (replay protection). Client must request a limited-use token or every call after the first fails. |
| `secrets: [SECRET]` | Required for `SECRET.value()` to be populated. |
| `memory`, `cpu`, `timeoutSeconds`, `concurrency`, `minInstances`, `maxInstances`, `region` | See `runtime-options.md`. |
| `cors` | Accepted by the type but pointless — callables answer CORS themselves. Do not set it. |
| `invoker` | Not a callable option. Callables are always publicly invokable; gate in the handler. |

## `CallableRequest<T>` fields

```ts
request.data;               // T — whatever the client sent; treat as unknown until parsed
request.auth;               // AuthData | undefined
request.auth?.uid;          // string
request.auth?.token;        // DecodedIdToken: email, email_verified, firebase.sign_in_provider, custom claims (token.role)
request.app;                // AppCheckData | undefined — { appId, token, alreadyConsumed? }
request.instanceIdToken;    // string | undefined — FCM token if the client SDK sent it
request.rawRequest;         // express.Request — headers, ip; rarely needed
request.acceptsStreaming;   // boolean — client called .stream() (firebase-functions ≥ 6.2)
```

`request.auth` is `undefined` for signed-out callers. `request.app` is `undefined` when no App Check token was sent and `enforceAppCheck` is false; with `enforceAppCheck: true` the SDK rejects the request before the handler runs, so `request.app` is always set inside the handler.

## Step 1 — authenticate

```ts
if (!request.auth) {
  throw new HttpsError("unauthenticated", "Sign in required");
}
const uid = request.auth.uid;
```

Anonymous users are authenticated. To require a permanent account:

```ts
if (request.auth.token.firebase.sign_in_provider === "anonymous") {
  throw new HttpsError("permission-denied", "Link an account to continue", { reason: "anonymous" });
}
```

Role checks read custom claims from the token (set by `getAuth().setCustomUserClaims`); the client must force-refresh its token after a claim change or the callable sees the old value:

```ts
if (request.auth.token.role !== "admin") {
  throw new HttpsError("permission-denied", "Admin only");
}
```

Put these in `src/lib/auth.ts` helpers (`requireAuth(request)`, `requireRole(request, "admin")`) that return the narrowed `AuthData` so the handler body does not repeat the optional check.

## Step 2 — validate with zod

```ts
// src/lib/validate.ts
import { HttpsError } from "firebase-functions/v2/https";
import type { ZodType } from "zod";

export function parse<T>(schema: ZodType<T>, data: unknown): T {
  const result = schema.safeParse(data);
  if (!result.success) {
    throw new HttpsError("invalid-argument", "Invalid input", {
      issues: result.error.issues.map((i) => ({ path: i.path.join("."), message: i.message })),
    });
  }
  return result.data;
}
```

Schema rules:

- Bound every string (`.max()`), every array (`.max()`), every number (`.int().min().max()`). Unbounded input is a cost and abuse vector.
- Use `.strict()` on objects the client fully controls so unknown keys are rejected rather than silently dropped; use the default (strip) for forward-compatible payloads where a newer app may send fields an older function ignores.
- Enums as `z.enum(["free", "pro"])`. Dates as `z.string().datetime()` (ISO-8601), never as numbers unless documented as epoch millis.
- IDs as `z.string().min(1).max(128)`; Firestore document IDs must not contain `/`.
- `z.infer<typeof Schema>` is the handler's input type. Type the handler as `CallableRequest<unknown>` so nobody reads `request.data.x` before parsing.

## Step 3 — authorise

Authentication says who; authorisation says whether they may touch this resource. Do it against the document, not the input:

```ts
const noteRef = db.doc(`users/${uid}/notes/${input.noteId}`); // path includes uid → cannot reach another user's note
```

For shared resources, read the document and check ownership inside the same transaction that mutates it. Throw `not-found` for documents that do not exist and `permission-denied` for ones the caller may not access. Do not distinguish the two for private resources when that would leak existence — return `not-found` for both.

## Step 5 — return shape

Return a plain object. The SDK wraps it as `{ "result": ... }` on the wire; the iOS `Callable<Req, Res>` decodes only the inner value.

```ts
return {
  id: noteRef.id,
  createdAt: new Date().toISOString(),  // string
  tags: input.tags,                      // string[]
  owner: null,                           // null is fine; undefined is dropped
};
```

Rules:

- Convert `Timestamp` → `ts.toDate().toISOString()`, `DocumentReference` → `ref.path`, `GeoPoint` → `{ latitude, longitude }`. Non-plain objects throw at serialisation and surface as `internal`.
- Never return `snapshot.data()` directly; it carries `Timestamp` values and any field the client should not see. Map to an explicit output type.
- Return `{}` rather than `undefined` for void operations; the iOS side then decodes an empty struct.
- Keep envelopes consistent across functions. See `firebase-ios-contract` → `references/envelope-and-naming.md`.

## Streaming callables (firebase-functions ≥ 6.2, Jan 2025)

The handler receives a second argument, `response: CallableResponse<Chunk>`. Chunks are delivered to the client as server-sent events; the return value is delivered last.

```ts
export const chat = onCall(
  { enforceAppCheck: true, secrets: [GEMINI_API_KEY], timeoutSeconds: 120 },
  async (request, response) => {
    const auth = requireAuth(request);
    const { prompt } = parse(ChatInput, request.data);

    const ai = getGenAI(GEMINI_API_KEY.value());
    const stream = await ai.models.generateContentStream({ model: "gemini-2.5-flash", contents: prompt });

    let full = "";
    for await (const chunk of stream) {
      const text = chunk.text ?? "";
      full += text;
      if (request.acceptsStreaming) {
        response.sendChunk({ text });   // Chunk — any JSON-serialisable value
      }
    }
    logger.info("chat.completed", { uid: auth.uid, chars: full.length });
    return { text: full };             // final result; non-streaming clients get only this
  },
);
```

- Check `request.acceptsStreaming` before `sendChunk`. Clients using `call()` instead of `stream()` set it false; calling `sendChunk` anyway is harmless but wasteful.
- Always `return` the complete result. The iOS `stream()` API yields `.message(chunk)` per `sendChunk` and `.result(final)` once for the return value.
- Throwing after chunks have been sent still delivers an error to the client; the iOS `for try await` throws. Validate everything before the first `sendChunk` so errors are cheap.
- Streaming needs the streaming-capable client: Firebase iOS SDK ≥ 11.8 (`Callable.stream(_:)`).
- `timeoutSeconds` applies to the whole stream. Long generations need a higher timeout, not a background task.

## `onCallGenkit`

If the AI logic is a Genkit flow, expose it with `onCallGenkit` instead of hand-wiring streaming:

```ts
import { onCallGenkit } from "firebase-functions/https";
import { GEMINI_API_KEY } from "../lib/params.js";
import { chatFlow } from "./flows.js";

export const chat = onCallGenkit(
  {
    secrets: [GEMINI_API_KEY],
    enforceAppCheck: true,
    authPolicy: (auth) => !!auth?.uid,   // reject unauthenticated; throws unauthenticated for you
  },
  chatFlow,
);
```

It streams automatically when the flow defines `streamSchema` and the client calls `stream()`. Input validation is the flow's `inputSchema` (zod); a mismatch surfaces as `invalid-argument`. Verify the current `onCallGenkit` options against firebase docs — `authPolicy` is the documented hook, but the signature has moved between minor versions.

## Testing a callable

```ts
import functionsTest from "firebase-functions-test";
import { describe, it, expect, afterAll } from "vitest";
import { createNote } from "../src/notes/createNote.js";

const test = functionsTest({ projectId: "demo-snaptool" });
const wrapped = test.wrap(createNote);

describe("createNote", () => {
  it("rejects unauthenticated", async () => {
    await expect(wrapped({ data: { title: "x" } })).rejects.toMatchObject({ code: "unauthenticated" });
  });

  it("creates for a signed-in user", async () => {
    const res = await wrapped({ data: { title: "Hi" }, auth: { uid: "u1", token: {} } });
    expect(res.id).toBeTruthy();
  });

  afterAll(() => test.cleanup());
});
```

Run under `firebase emulators:exec --only firestore,auth "vitest run"` so `db` hits the emulator (`FIRESTORE_EMULATOR_HOST` is set for you).

## Does not exist / common mistakes

- `onCall((data, context) => ...)` — v1 signature. v2 is `(request)`.
- `context.auth`, `context.app`, `context.rawRequest` — v1. Use `request.auth` etc.
- `request.auth.uid` without checking `request.auth` — TypeError → `internal`. Guard first.
- `onCall({ cors: true }, ...)` — no effect on callables.
- `onCall({ invoker: "public" }, ...)` — not a callable option.
- Returning a `Timestamp`, `DocumentSnapshot`, `Date` inside nested objects (Date does serialise to ISO via JSON, but be explicit), `Map`, `Set`, or a class instance.
- `response.write(...)` / `response.end()` in a callable — that is express; callables use `response.sendChunk` and `return`.
- `request.data` typed as the input type without parsing — the generic on `CallableRequest<T>` is a promise you make, not a check the SDK performs.

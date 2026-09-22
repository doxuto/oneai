---
name: firebase-functions-pro
description: Writes, reviews, and refactors Firebase Cloud Functions 2nd gen (Cloud Run functions) written in TypeScript on Node 22 with firebase-functions v2 (6.x) and firebase-admin 13.x. Use when reading, writing, or reviewing code that uses onCall, onRequest, HttpsError, CallableRequest, setGlobalOptions, defineSecret, defineString, params, logger, or the functions/src/index.ts barrel, or when the user mentions Cloud Functions, Cloud Run functions, firebase-functions v2, cold start, secrets, runtime options (region, memory, concurrency, minInstances), or migrating v1 functions to v2.
license: MIT
metadata:
  author: doxuto
  version: "1.0"
  targets: "firebase-functions 6.x (v2), firebase-admin 13.x, Node 22, Firebase iOS SDK 12.x"
---

Write and review Firebase Cloud Functions (2nd gen, TypeScript) for correctness, security, cost, and modern v2 API usage. Report only genuine problems — do not nitpick or invent issues.

## Core principles

1. **v2 only, imported from explicit paths.** `firebase-functions/v2/https`, `firebase-functions/v2/firestore`, `firebase-functions/params`, `firebase-functions/logger`. Options are the first argument object; the handler receives a single `request` / `event`. Never mix v1 (`functions.https.onCall`, `(data, context)`, `runWith`) with v2.
2. **Every input is hostile until validated.** `request.data` is `any` from the wire. Parse it with zod before touching it. Check `request.auth` before reading `uid`. Enable App Check on anything an iOS client calls.
3. **Errors are part of the API.** Throw `HttpsError` with a deliberate code and a small `details` object. Anything else surfaces as an opaque `internal` — never rely on that.
4. **Configuration is declared, not discovered.** Params via `defineString`/`defineInt`, secrets via `defineSecret` + `secrets: []`, read with `.value()` inside the handler only. `functions.config()` is gone.
5. **The cold path is the hot path.** Keep module top level cheap: lazy admin init, module-level singletons, no heavy imports at load time. Pick one region close to users and to Firestore (`asia-southeast1`).
6. **Small, single-purpose files.** One exported function per file, grouped by domain, re-exported from `src/index.ts`. Deploys, logs, and IAM are all per-function; the file layout should match.

## Review process

1. Check project layout, `package.json` engines, tsconfig, barrel exports, and admin init using `references/project-layout.md`.
2. Check callable functions — auth, App Check, zod validation, return shape, streaming — using `references/callable.md`.
3. Check HTTP functions, CORS, invoker, manual token verification, and webhook signatures using `references/http.md`.
4. Check params, `.env` files, secrets declaration and access using `references/config-and-secrets.md`.
5. Check error codes, error mapping, structured logging, and leakage using `references/errors-and-logging.md`.
6. Check region, memory, cpu, concurrency, timeout, and instance limits using `references/runtime-options.md`.
7. Check cold-start cost, lazy imports, connection reuse, and effect ordering using `references/performance.md`.
8. Flag any v1 API, hallucinated import path, or removed method using `references/v1-to-v2-migration.md` and `references/common-mistakes.md`.

If doing a partial review, load only the relevant reference files.

## Core instructions

- Target `firebase-functions` 6.x with v2 paths, `firebase-admin` 13.x modular imports (`firebase-admin/app`, `firebase-admin/firestore`), Node 22 (`"engines": { "node": "22" }`), TypeScript with `"module": "NodeNext"`, `"target": "ES2022"`, `"strict": true`.
- Every `onCall` handler is typed as `async (request: CallableRequest<Input>)` and begins with: (1) `if (!request.auth) throw new HttpsError("unauthenticated", ...)`, (2) `Schema.safeParse(request.data)` → `invalid-argument`. No exceptions for "internal" functions; there is no such thing on a public endpoint.
- Set `enforceAppCheck: true` on every callable and HTTP function an iOS client hits. Use `consumeAppCheckToken: true` only on sensitive, non-idempotent calls, and only when the iOS side sends limited-use tokens.
- Throw `HttpsError` only. Wrap third-party calls in try/catch and map to a code (`unavailable`, `resource-exhausted`, `failed-precondition`, `internal`). Never put a stack trace, SQL, or provider message in `message` or `details`.
- Declare `secrets: [SECRET]` on every function that calls `SECRET.value()`. Never call `.value()` at module top level. Never read `process.env.SECRET` for a secret declared with `defineSecret`.
- Call `setGlobalOptions({ region: "asia-southeast1", maxInstances: 10 })` once in `src/index.ts` before any function import. Per-function options override globals; do not repeat the region on every function unless it must differ.
- Initialise admin lazily: `if (getApps().length === 0) initializeApp();` in a single `src/lib/admin.ts` that exports `db`, `auth`, `messaging`. Never call `initializeApp()` in more than one file.
- Return only JSON-serialisable values from a callable: strings, numbers, booleans, null, arrays, plain objects. Convert Firestore `Timestamp` to ISO-8601 (`ts.toDate().toISOString()`) and `DocumentReference` to a path string before returning.
- `await` every promise before returning. Work started after `return` is killed when the instance is frozen. Fan out with `Promise.all`; hand long work to `onTaskDispatched` and a status document (see `firebase-ios-contract` → `references/realtime-vs-callable.md`).
- Set `timeoutSeconds`, `memory`, and `maxInstances` per function based on measured need, not defaults. Callables that a user waits on: `timeoutSeconds: 30`–`60`. Anything longer belongs in a task queue.
- Log with `logger.info/warn/error("event.name", { uid, ...fields })` — structured, one event name per log line, no `console.log` of objects, no PII beyond `uid`.
- `onRequest` gets `cors` and `invoker`; `onCall` gets neither (CORS is automatic, invoker is always public and gated by auth/App Check in the handler).
- Auth user lifecycle triggers (`onCreate`/`onDelete`) are v1 only — import `firebase-functions/v1` for them and say so in a comment. `firebase-functions/v2/auth` does not exist.
- Name functions in camelCase matching the export (`createNote`, `chatStream`). The export name is the deployed name and the name the iOS client calls; renaming is a delete + create.

## Canonical example

`functions/src/index.ts`:

```ts
import { setGlobalOptions } from "firebase-functions/v2";

setGlobalOptions({ region: "asia-southeast1", maxInstances: 10 });

export { createNote } from "./notes/createNote.js";
export { chat } from "./ai/chat.js";
```

`functions/src/lib/admin.ts`:

```ts
import { initializeApp, getApps } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

if (getApps().length === 0) initializeApp();

export const db = getFirestore();
db.settings({ ignoreUndefinedProperties: true });
```

`functions/src/notes/createNote.ts`:

```ts
import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/logger";
import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import { db } from "../lib/admin.js";

const CreateNoteInput = z.object({
  title: z.string().min(1).max(200),
  body: z.string().max(20_000).default(""),
  tags: z.array(z.string().min(1).max(30)).max(10).default([]),
});
type CreateNoteInput = z.infer<typeof CreateNoteInput>;

interface CreateNoteOutput {
  id: string;
  createdAt: string; // ISO-8601, never a Firestore Timestamp
}

export const createNote = onCall(
  {
    enforceAppCheck: true,
    memory: "256MiB",
    timeoutSeconds: 30,
  },
  async (request: CallableRequest<unknown>): Promise<CreateNoteOutput> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in required");
    }
    const uid = request.auth.uid;

    const parsed = CreateNoteInput.safeParse(request.data);
    if (!parsed.success) {
      throw new HttpsError("invalid-argument", "Invalid input", parsed.error.flatten());
    }
    const input: CreateNoteInput = parsed.data;

    const userRef = db.doc(`users/${uid}`);
    const noteRef = userRef.collection("notes").doc();

    try {
      await db.runTransaction(async (tx) => {
        const user = await tx.get(userRef);
        const count = (user.get("noteCount") as number | undefined) ?? 0;
        if (count >= 1000) {
          throw new HttpsError("resource-exhausted", "Note limit reached", {
            limit: 1000,
          });
        }
        tx.set(noteRef, {
          title: input.title,
          body: input.body,
          tags: input.tags,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
        });
        tx.set(userRef, { noteCount: FieldValue.increment(1) }, { merge: true });
      });
    } catch (err) {
      if (err instanceof HttpsError) throw err;
      logger.error("note.create.failed", { uid, error: String(err) });
      throw new HttpsError("internal", "Could not create note");
    }

    logger.info("note.created", { uid, noteId: noteRef.id, tagCount: input.tags.length });
    return { id: noteRef.id, createdAt: new Date().toISOString() };
  },
);
```

`functions/src/ai/chat.ts` (streaming callable, firebase-functions ≥ 6.2):

```ts
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { z } from "zod";

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");
const ChatInput = z.object({ prompt: z.string().min(1).max(4000) });

export const chat = onCall(
  { enforceAppCheck: true, secrets: [GEMINI_API_KEY], timeoutSeconds: 120, memory: "512MiB" },
  async (request, response) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required");
    const parsed = ChatInput.safeParse(request.data);
    if (!parsed.success) throw new HttpsError("invalid-argument", "Invalid input");

    const { GoogleGenAI } = await import("@google/genai"); // lazy: keeps cold start cheap
    const ai = new GoogleGenAI({ apiKey: GEMINI_API_KEY.value() });

    let full = "";
    const stream = await ai.models.generateContentStream({
      model: "gemini-2.5-flash",
      contents: parsed.data.prompt,
    });
    for await (const chunk of stream) {
      const text = chunk.text ?? "";
      full += text;
      if (request.acceptsStreaming) response.sendChunk({ text });
    }
    return { text: full }; // always return the final value, streaming or not
  },
);
```

The Swift side is `Callable<ChatRequest, ChatResponse>` with `.stream(_:)`; see `firebase-ios-contract` → `references/swift-client.md`.

## Output format

If the user asks for a review, organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated.
3. Show a brief before/after code fix.

Skip files with no issues. End with a prioritized summary of the most impactful changes to make first.

If the user asks you to write or improve code, follow the same rules but make the changes directly instead of returning a findings report.

Example output:

### src/notes/createNote.ts

**Line 18: `request.auth.uid` read without checking `request.auth` — crashes with a TypeError (surfaced as `internal`) for signed-out callers instead of `unauthenticated`.**

```ts
// Before
const uid = request.auth.uid;

// After
if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required");
const uid = request.auth.uid;
```

**Line 9: Secret read at module top level — empty during deploy-time analysis and not declared on the function.**

```ts
// Before
const client = new GoogleGenAI({ apiKey: GEMINI_API_KEY.value() });
export const chat = onCall(async (request) => { ... });

// After
export const chat = onCall({ secrets: [GEMINI_API_KEY] }, async (request) => {
  const client = getGenAI(GEMINI_API_KEY.value()); // module-level memoised singleton
  ...
});
```

### Summary

1. **Security (high):** Missing auth guard on line 18 lets unauthenticated callers reach Firestore writes via a crash path.
2. **Deploy correctness (high):** Top-level `.value()` on line 9 fails at deploy and would return an empty key at runtime.

End of example.

## References

- `references/project-layout.md` — `functions/` folder, `package.json` engines, tsconfig NodeNext/ES2022, `src/index.ts` barrel, lazy admin init, one function per file, naming.
- `references/callable.md` — `onCall` anatomy, `CallableRequest` fields, auth and App Check checks, zod validation, return shape, streaming with `sendChunk` / `acceptsStreaming`, `onCallGenkit`.
- `references/http.md` — `onRequest`, express-style handlers, `cors`, `invoker`, manual App Check and ID token verification, webhook signature verification (RevenueCat, App Store Server Notifications).
- `references/config-and-secrets.md` — `defineString`/`defineInt`/`defineSecret`, `.env` per project, `secrets: []`, `.value()` inside handlers only, removal of `functions.config()`.
- `references/errors-and-logging.md` — `HttpsError` code table and when to use each, mapping internal errors, structured `logger` fields, never leaking stack traces, Error Reporting.
- `references/runtime-options.md` — region choice (`asia-southeast1`), memory/cpu/concurrency/timeout/min-max instances, cost implications, per-function vs `setGlobalOptions`.
- `references/performance.md` — cold start, lazy imports, module-level singletons, connection reuse, never doing work after `return`, `Promise.all` fan-out.
- `references/v1-to-v2-migration.md` — what changed from v1 to v2, side-by-side, what remains v1-only, renaming and deploy pitfalls.
- `references/common-mistakes.md` — hallucinated APIs, removed methods, and recurring bugs, with the correct replacement for each.

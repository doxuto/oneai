# Performance

Two costs dominate: cold start (time from a new instance being scheduled to the first request being served) and per-request latency to Firestore or an upstream API. Both are mostly decided by what happens at module top level and how promises are sequenced.

## Cold start anatomy

1. Container scheduled, Node started.
2. `lib/index.js` evaluated — every `import` in the barrel, transitively. This is where the time goes.
3. The framework wires the requested function.
4. Your handler runs.

Step 2 loads **every function's module**, not only the one being invoked, because the barrel imports them all. A heavy import in `ai/chat.ts` slows the cold start of `notes/createNote` too.

Measure: Cloud Logging shows `Function execution took N ms` per request; cold starts are the outliers on a fresh instance. Locally, `node --cpu-prof lib/index.js` or `NODE_DEBUG=module` shows what loads at import.

## Keep top level cheap

```ts
// BAD — evaluated on every cold start of every function
import sharp from "sharp";
import { GoogleGenAI } from "@google/genai";
import { ImageAnnotatorClient } from "@google-cloud/vision";
const ai = new GoogleGenAI({ apiKey: process.env.KEY });
const vision = new ImageAnnotatorClient();
```

```ts
// GOOD — lazy, memoised, created inside the request on first use
let ai: import("@google/genai").GoogleGenAI | undefined;
async function getGenAI(): Promise<import("@google/genai").GoogleGenAI> {
  if (!ai) {
    const { GoogleGenAI } = await import("@google/genai");
    ai = new GoogleGenAI({ apiKey: GEMINI_API_KEY.value() });
  }
  return ai;
}
```

Rules:

- `firebase-functions`, `firebase-admin/app`, `firebase-admin/firestore`, and `zod` at top level are fine — every function needs them and they are already in memory.
- Anything over ~50 ms to import (`sharp`, `@google-cloud/vision`, `@google/genai`, `pdf-lib`, `@apple/app-store-server-library`, `express` for non-HTTP functions) is a dynamic `await import()` inside a getter.
- Never build clients at top level from secrets — `.value()` is empty there anyway.
- Do not `import` a module just for its types; use `import type` so it is erased.
- Check `lib/index.js` after build: `grep -c "require\|import" lib/index.js` should be small.

## Module-level singletons

Module scope survives across requests on the same instance (and across concurrent requests with `concurrency > 1`). Use it for things that are expensive to create and safe to share:

```ts
// src/lib/admin.ts — one Firestore client per instance
export const db = getFirestore();

// src/ai/_shared.ts — one GenAI client per instance
let genai: GoogleGenAI | undefined;
export function getGenAI() { return (genai ??= new GoogleGenAI({ apiKey: GEMINI_API_KEY.value() })); }

// src/lib/http.ts — one keep-alive agent per instance
import { Agent } from "undici";
export const agent = new Agent({ keepAliveTimeout: 30_000, connections: 32 });
```

Never keep per-request state in module scope. With concurrency 80, `let currentUser` is shared by 80 requests.

## Connection reuse

- `firebase-admin` clients (`getFirestore()`, `getAuth()`) keep gRPC channels open. Create once, reuse. Creating a new one per request is the classic cause of "Firestore is slow in functions".
- Node 22's global `fetch` (undici) reuses connections per origin by default. Pass a shared `dispatcher` only when you need tuned pool sizes.
- Third-party SDKs that wrap axios or node-fetch: construct once at module level (lazily) so their agent pool persists.
- Enable Firestore's `preferRest: true` in `db.settings()` only if profiling shows gRPC channel setup dominating and the workload is small reads — it trades throughput for a faster first call. Measure before enabling.

## Never do work after `return`

```ts
// BAD — the instance may be frozen or killed the moment the response is sent
export const createNote = onCall({}, async (request) => {
  const id = await write();
  sendAnalytics(id);          // not awaited — may never run
  void warmCache(id);         // same
  return { id };
});
```

Cloud Run throttles CPU to near zero once the response is sent unless `cpu: "always"`-style allocation is configured (not exposed through firebase-functions options). Background promises stall, and if the instance is reclaimed they are lost with no log.

```ts
// GOOD — await it, or hand it off durably
export const createNote = onCall({}, async (request) => {
  const id = await write();
  await Promise.all([sendAnalytics(id), warmCache(id)]);   // in the response critical path, in parallel
  return { id };
});

// or, when it must not add latency: enqueue and return
await getFunctions().taskQueue("indexNote").enqueue({ id });
return { id };
```

Also applies to `setTimeout`, `setInterval`, and event-emitter callbacks that fire after the handler resolves.

## Fan-out with `Promise.all`

```ts
// BAD — sequential, N round trips
for (const id of ids) await db.doc(`notes/${id}`).delete();

// GOOD — parallel, one round trip of latency
await Promise.all(ids.map((id) => db.doc(`notes/${id}`).delete()));

// BETTER for Firestore writes — one commit
const batch = db.batch();
for (const id of ids) batch.delete(db.doc(`notes/${id}`));
await batch.commit();   // ≤ 500 ops per batch

// BEST for thousands — bulkWriter handles chunking, retries, and rate limiting
const writer = db.bulkWriter();
for (const id of ids) writer.delete(db.doc(`notes/${id}`));
await writer.close();
```

Reads: `db.getAll(...refs)` fetches many documents in one call. Use `Promise.allSettled` when partial failure is acceptable and you want to report per-item results; `Promise.all` rejects on the first failure and leaves the others running.

Cap fan-out width when hitting external APIs (`p-limit`, or a hand-rolled semaphore): 500 parallel Gemini calls trip rate limits and produce 500 `resource-exhausted` errors.

## Firestore access patterns

- Read the minimum: `select("title", "updatedAt")` on queries; `tx.get(ref)` only for documents you will conditionally write.
- Transactions: all reads first, then writes; keep them under ~10 documents; never call an external API inside one (it retries on contention and would call the API again).
- Avoid reading a document to check existence before `create()` — `create()` itself fails with code 6 when it exists.
- Paginate with `orderBy` + `startAfter(lastSnapshot)` + `limit`. `offset` reads and bills every skipped document.
- Cache immutable reference data (plan definitions, feature flags) in a module-level variable with a TTL, refreshed on first request after expiry, not on every call.

## Payload size

- Callable request and response bodies are limited (10 MB request on Cloud Run; keep well under 1 MB in practice). Images and files go through Storage; the callable receives a path.
- Do not return a full note list in one callable; paginate and let the client cache.
- Streaming callables reduce time-to-first-byte for AI output; they do not reduce total work.

## Bundling

`tsc` output with `node_modules` deployed as-is is the default and fine. Bundling with esbuild (`esbuild src/index.ts --bundle --platform=node --target=node22 --format=esm --outfile=lib/index.js --packages=external`) reduces file count and module resolution time by a few tens of milliseconds. Do it only if cold start is measured and matters, and keep `--packages=external` for native modules like `sharp`.

## Checklist for a cold-start review

1. `grep -n "^import" src/**/*.ts` — any heavy SDK at top level in a file the barrel imports?
2. Any `new SomeClient()` or `.value()` at module scope?
3. Any `initializeApp()` outside `lib/admin.ts`?
4. Handlers: any un-awaited promise before `return`?
5. Loops with `await` inside that could be `Promise.all` / batch / bulkWriter?
6. Per-function `memory`/`cpu`/`concurrency` set for I/O-bound callables?
7. `minInstances: 1` on the one or two launch-path callables in prod?

## Does not exist / common mistakes

- `functions.runWith({ minInstances: 1 })` — v1. Use the v2 options object.
- Relying on `process.on("beforeExit")` or `setTimeout` after the response to flush work — the instance is throttled; use a task queue.
- `import * as admin from "firebase-admin"` — loads every admin service (auth, messaging, storage, database, remote config, …) on cold start. Modular imports only.
- `new Firestore()` from `@google-cloud/firestore` alongside `getFirestore()` — two clients, two channels; use the admin one.
- Wrapping a callable body in `setTimeout(..., 0)` or `setImmediate` "to return faster" — the response is not sent until the returned promise resolves; you gained nothing and lost error handling.
- `Promise.all` over thousands of Gemini calls — rate limited; add a concurrency limit.

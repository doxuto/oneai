# v1 → v2 migration

2nd gen functions run on Cloud Run: concurrency, larger instances, longer HTTP timeouts, Eventarc-based triggers, per-function options as data instead of chained builders. `firebase-functions` 6.x exports v2 from the top-level subpaths (`firebase-functions/https`) and explicitly from `firebase-functions/v2/*`. This bundle always imports from `v2/*` so a reader can see the generation at a glance.

## What changed

| Area | v1 | v2 |
|---|---|---|
| Import | `import * as functions from "firebase-functions"` (or `/v1`) | `import { onCall } from "firebase-functions/v2/https"` etc. |
| Options | `functions.region("r").runWith({ memory: "1GB" }).https.onCall(...)` | `onCall({ region: "r", memory: "1GiB" }, ...)` |
| Global defaults | none (repeat on each function) | `setGlobalOptions({...})` from `firebase-functions/v2` |
| Callable handler | `(data, context) => {}` | `(request: CallableRequest) => {}` |
| Auth in callable | `context.auth` | `request.auth` |
| App Check in callable | `context.app` + `allowInvalidAppCheckToken` | `request.app` + `enforceAppCheck` / `consumeAppCheckToken` |
| Raw request | `context.rawRequest` | `request.rawRequest` |
| Firestore trigger | `functions.firestore.document("p/{id}").onCreate((snap, context) => {})` | `onDocumentCreated("p/{id}", (event) => { event.data; event.params })` |
| Trigger change | `(change, context)` → `change.before/after` | `event.data.before / event.data.after` |
| Trigger params | `context.params.id` | `event.params.id` |
| Event id | `context.eventId` | `event.id` |
| Scheduler | `functions.pubsub.schedule("every 5 minutes").timeZone("Asia/Ho_Chi_Minh").onRun(ctx => {})` | `onSchedule({ schedule: "every 5 minutes", timeZone: "Asia/Ho_Chi_Minh" }, (event) => {})` |
| Storage | `functions.storage.object().onFinalize((object) => {})` | `onObjectFinalized({ bucket }, (event) => { event.data })` |
| Tasks | `functions.tasks.taskQueue({...}).onDispatch((data, ctx) => {})` | `onTaskDispatched({...}, (req) => { req.data })` |
| Pub/Sub | `functions.pubsub.topic("t").onPublish((msg, ctx) => {})` | `onMessagePublished("t", (event) => { event.data.message.json })` from `v2/pubsub` |
| Memory strings | `"128MB" … "8GB"` | `"128MiB" … "32GiB"` |
| Max timeout | 540 s | 540 s (event, callable) / 3600 s (`onRequest`) |
| Concurrency | 1 | up to 1000 (default 80 when `cpu >= 1`) |
| Config | `functions.config()` | params + `defineSecret` |
| Logger | `functions.logger` | `import { logger } from "firebase-functions/logger"` (same API) |
| HTTP CORS | manual or `cors` package | `onRequest({ cors: [...] })` |
| Invoker | IAM via gcloud | `onRequest({ invoker })` |
| Deployed name | export name | export name (same), but the Cloud Run service name is lower-case and the URL differs |
| URL | `https://<region>-<project>.cloudfunctions.net/<name>` | `https://<name>-<hash>-<region>.a.run.app` (plus the `cloudfunctions.net` alias) |

## Side by side — callable

```ts
// v1
import * as functions from "firebase-functions/v1";

export const createNote = functions
  .region("asia-southeast1")
  .runWith({ memory: "512MB", timeoutSeconds: 60, secrets: ["GEMINI_API_KEY"] })
  .https.onCall(async (data, context) => {
    if (!context.auth) throw new functions.https.HttpsError("unauthenticated", "Sign in");
    const title = data.title as string;
    return { id: "..." };
  });
```

```ts
// v2
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { GEMINI_API_KEY } from "../lib/params.js";

export const createNote = onCall(
  { region: "asia-southeast1", memory: "512MiB", timeoutSeconds: 60, secrets: [GEMINI_API_KEY], enforceAppCheck: true },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in");
    const { title } = parse(Input, request.data);
    return { id: "..." };
  },
);
```

## Side by side — Firestore trigger

```ts
// v1
export const onNoteUpdated = functions.firestore
  .document("users/{uid}/notes/{noteId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const { uid, noteId } = context.params;
  });
```

```ts
// v2
import { onDocumentUpdated } from "firebase-functions/v2/firestore";

export const onNoteUpdated = onDocumentUpdated("users/{uid}/notes/{noteId}", async (event) => {
  if (!event.data) return;
  const before = event.data.before.data();
  const after = event.data.after.data();
  const { uid, noteId } = event.params;
  // event.id for idempotency; event.time is an RFC3339 string
});
```

Note `event.data` is optional in the type (`Change<QueryDocumentSnapshot> | undefined`); guard it.

## Side by side — scheduler

```ts
// v1
export const nightly = functions.pubsub.schedule("0 3 * * *").timeZone("Asia/Ho_Chi_Minh").onRun(async () => {});

// v2
import { onSchedule } from "firebase-functions/v2/scheduler";
export const nightly = onSchedule({ schedule: "0 3 * * *", timeZone: "Asia/Ho_Chi_Minh", retryCount: 3 }, async (event) => {
  // event.scheduleTime
});
```

## Still v1 only

These have no v2 equivalent. Import them from `firebase-functions/v1` and mark the file with a comment.

```ts
// src/users/onUserDeleted.ts
// v1 ONLY: Auth user lifecycle triggers do not exist in v2.
import * as functionsV1 from "firebase-functions/v1";
import { db } from "../lib/admin.js";

export const onUserDeleted = functionsV1
  .region("asia-southeast1")
  .auth.user()
  .onDelete(async (user) => {
    await db.recursiveDelete(db.doc(`users/${user.uid}`));
  });

export const onUserCreated = functionsV1
  .region("asia-southeast1")
  .auth.user()
  .onCreate(async (user) => {
    await db.doc(`users/${user.uid}`).create({ createdAt: new Date(), plan: "free" });
  });
```

- `auth.user().onCreate` / `.onDelete` — v1 only.
- `analytics.event(...).onLog` — v1 only.
- `testLab.testMatrix().onComplete` — v1 only.
- Realtime Database triggers exist in both (`firebase-functions/v2/database`); Remote Config `onConfigUpdated` exists in v2 (`v2/remoteConfig`).

v2 **blocking** identity triggers are a different thing: `beforeUserCreated` / `beforeUserSignedIn` from `firebase-functions/v2/identity` run synchronously during sign-up/sign-in, can reject or modify the user, and require the project to be upgraded to Identity Platform. They do not replace `onCreate`/`onDelete`.

v1 and v2 functions coexist in one codebase and one deploy. Mixing is fine at the project level; mixing APIs *within one function* is not.

## Migration procedure

Changing a function from v1 to v2 is a delete and a create, not an update. The CLI refuses to upgrade in place: `Function X is a 1st gen function; cannot change to 2nd gen`.

For callables and HTTP functions the iOS app calls:

1. Add the v2 function under a **new name** (`createNoteV2`, or a new domain name) and deploy. Both run.
2. Ship an iOS build that calls the new name. For a callable, the old app keeps working against the old function.
3. When the old build's share drops below your threshold, remove the v1 export and deploy; confirm deletion when the CLI asks (or `firebase functions:delete createNote --region asia-southeast1`).
4. Optionally rename back later — again as delete + create — only if the name matters more than the churn. Usually it does not; keep `V2`.

For triggers (nobody calls them by name):

1. Deploy the v2 trigger under a new name alongside the v1 one. Both fire for every event, so make the handler idempotent or gate the v2 one behind a flag for a release.
2. Delete the v1 export, deploy.
3. Rename if desired (delete + create; a gap of a few seconds where neither is deployed — acceptable for most triggers, not for billing-critical ones; use the overlap approach there too).

For scheduled functions: deploy new, delete old; overlapping runs for one interval are the only risk.

Renaming also changes the Cloud Run service, its URL, its logs, and its IAM bindings. Any `invoker` grants or Cloud Scheduler OIDC targets pointing at the old name must be updated.

## Deploy pitfalls

- Region change is also delete + create. Plan it like a rename.
- v2 functions need the Cloud Run, Eventarc, Artifact Registry, and Cloud Build APIs enabled; the CLI enables them on first deploy but this can take a minute and the first deploy may fail with a permissions race — re-run.
- Firestore triggers in v2 require the Eventarc service agent to have `roles/eventarc.serviceAgent`; the CLI sets it up, but a manually locked-down project may need it granted.
- The runtime service account changed: v1 used the App Engine default SA, v2 uses the Compute Engine default SA. Custom IAM grants on the App Engine SA do not carry over.
- `firebase-functions-test` 3.x wraps v2 functions with `test.wrap(fn)` taking `{ data, auth, app, rawRequest }` for callables and `{ data, params }` for events — the v1 `(data, context)` shape is gone.

## Does not exist / common mistakes

- `firebase-functions/v2/auth` — does not exist. Lifecycle triggers are v1; blocking triggers are `v2/identity`.
- `onCall(...).runWith(...)` or `onCall({...}).region(...)` — no builder chaining in v2.
- `functions.https.onCall({ region: "x" }, (data, context) => ...)` — v1 builder with a v2 options object; the options are ignored or rejected.
- `functions.config()` in a v2 function — deprecated and removed.
- `memory: "1GB"` in v2 — must be `"1GiB"`.
- Expecting `firebase deploy` to upgrade a v1 function in place — it will not; rename.
- `context.eventId` in a v2 trigger — it is `event.id`.
- `change.before` in a v2 update trigger — it is `event.data.before` (and `event.data` may be undefined).
- Assuming the v2 URL is `cloudfunctions.net/<name>` — it exists as an alias, but the canonical URL is `run.app`; do not hard-code either in the app; use the SDK.

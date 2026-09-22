# Versioning

An installed iOS build is a client you cannot update. Every deployed callable is called by every app version still in use, for months. The contract evolves under two rules: **additive changes in place**, **breaking changes under a new name**.

## What is additive (safe, same function)

| Change | Server | Client (new build) | Old builds |
|---|---|---|---|
| Add an optional request field | `z.string().optional()` or `.default()` | Add `var x: T? = nil` | Do not send it; server applies default |
| Add a response field | Add to output interface, always populate | Add `let x: T` (or `T?` while the server rolls out) | Ignore unknown keys (Codable default) |
| Add an enum case in a **response** | Extend `z.enum` / union | Add case; keep `unknown` fallback | Decode as `unknown` — only safe if the fallback exists |
| Accept a new enum case in a **request** | Extend `z.enum` | Add case | Unaffected |
| Loosen validation (raise a max) | `.max(200)` → `.max(500)` | Nothing | Unaffected |
| Add a new error `details` key | Add key | Add optional property | Ignore |
| Add a new function | New file + export | New closure in the client | Unaffected |

Rule for new response fields: deploy the server first, then ship the app. Never ship an app that requires a field the deployed server does not yet return.

Rule for new request fields: ship with a default on the server so older builds' omission is valid.

## What is breaking (new function name)

- Rename or remove a request or response field.
- Change a field's type (`string` → `number`, `T` → `T[]`, required → `null`able in a response).
- Make an optional request field required.
- Tighten validation so previously valid input fails (`.max(500)` → `.max(200)`).
- Remove an enum case the client may send, or one it may receive without an `unknown` fallback.
- Change semantics without changing shape (what `limit` means, what `visibility: "shared"` grants). This is the one reviewers miss.
- Change the function's region, or move it from v1 to v2 (delete + create under the hood — see `firebase-functions-pro` → `references/v1-to-v2-migration.md`).

Any of these: create `createNoteV2` (or a better verb: `createNoteWithAttachments`), keep `createNote` deployed and unchanged, migrate the client, retire the old one later.

```ts
// functions/src/notes/createNoteV2.ts
export const createNoteV2 = onCall({ enforceAppCheck: true }, async (request) => { ... });

// index.ts keeps both
export { createNote } from "./notes/createNote.js";       // legacy — remove after 2026-12 (min app 2.4)
export { createNoteV2 } from "./notes/createNoteV2.js";
```

Share implementation between versions with an internal service function; keep the two `onCall` wrappers as thin adapters that translate input/output shapes.

## Deprecating fields

1. Server keeps populating the old field and adds the new one. Comment the old field with the removal condition (`// deprecated since 2.3.0; remove when minAppVersion >= 2.3.0`).
2. New client reads the new field.
3. When the minimum supported app version is past the switch, stop populating (return `null` if the type allows) and eventually remove — the removal is itself breaking only for builds below the minimum, which the version gate already rejects.

Never remove a response field in one step "because the new app does not use it".

For request fields: keep accepting the old field, map it to the new one on the server, log a warning with the app version so you can see when it stops arriving.

## Minimum app version gate

The server refuses builds that are too old with `failed-precondition` and a `details.minVersion` the client can show. Centralise it so no callable forgets.

Client sends its version on every call. The Functions SDK does not do this for you; put it in the request envelope as a standard field:

```swift
struct ClientInfo: Codable, Equatable, Sendable {
  var appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
  var build: String = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
  var platform = "ios"
}

struct CreateNoteRequest: Codable, Equatable, Sendable {
  var client = ClientInfo()
  var title: String
  var body: String = ""
}
```

Server validates and gates in the shared `parse` step:

```ts
// src/lib/validate.ts
import { HttpsError } from "firebase-functions/v2/https";
import { z, type ZodType } from "zod";
import { MIN_APP_VERSION } from "./params.js";

export const ClientInfo = z.object({
  appVersion: z.string().regex(/^\d+(\.\d+){0,2}$/),
  build: z.string().max(20),
  platform: z.enum(["ios"]),
});

function compareSemver(a: string, b: string): number {
  const pa = a.split(".").map(Number), pb = b.split(".").map(Number);
  for (let i = 0; i < 3; i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d !== 0) return d;
  }
  return 0;
}

export function requireMinVersion(client: z.infer<typeof ClientInfo>): void {
  const min = MIN_APP_VERSION.value();
  if (compareSemver(client.appVersion, min) < 0) {
    throw new HttpsError("failed-precondition", "App update required", { reason: "appOutdated", minVersion: min });
  }
}

export function parse<T extends { client: z.infer<typeof ClientInfo> }>(schema: ZodType<T>, data: unknown): T {
  const result = schema.safeParse(data);
  if (!result.success) throw new HttpsError("invalid-argument", "Invalid input", { issues: result.error.issues.map((i) => ({ path: i.path.join("."), message: i.message })) });
  requireMinVersion(result.data.client);
  return result.data;
}
```

`MIN_APP_VERSION` is a `defineString` param in `.env.<projectId>`; raising it is a deploy, not a code change. Per-function minimums (a new feature that needs 2.5.0) call `requireMinVersion` with an explicit floor.

Client handles it once, at the root feature:

```swift
case let .apiFailure(error) where error.kind == .precondition(reason: "appOutdated"):
  state.destination = .forceUpdate(ForceUpdate.State(minVersion: error.details?.minVersion ?? ""))
  return .none
```

Every feature that receives an `APIError` forwards `.precondition(reason: "appOutdated")` to the root via a delegate action, the same way `.unauthenticated` is forwarded (`tca-integration.md`).

Do not gate on `build` number across TestFlight and App Store; gate on `appVersion` (marketing version) and keep it monotonic.

## Feature flags via Remote Config

Version gates say "too old". Feature flags say "not for you yet". Use Firebase Remote Config for the second, read on the client, and mirror the decision on the server for anything that costs money.

Client (`FirebaseRemoteConfig`, wrapped in a `@DependencyClient`):

```swift
@DependencyClient
struct FeatureFlags: Sendable {
  var isEnabled: @Sendable (_ key: FlagKey) -> Bool = { _ in false }
  var refresh: @Sendable () async throws -> Void
}

enum FlagKey: String { case aiChat = "ai_chat_enabled", ocr = "ocr_enabled" }

extension FeatureFlags: DependencyKey {
  static let liveValue: FeatureFlags = {
    let rc = RemoteConfig.remoteConfig()
    rc.setDefaults(["ai_chat_enabled": false as NSObject, "ocr_enabled": false as NSObject])
    return FeatureFlags(
      isEnabled: { rc.configValue(forKey: $0.rawValue).boolValue },
      refresh: { _ = try await rc.fetchAndActivate() }
    )
  }()
}
```

Server: a `defineBoolean("FEATURE_OCR")` param or a `config/features` Firestore doc read with a module-level TTL cache. When off, throw `unimplemented` so the client hides the feature rather than showing an error:

```ts
if (!FEATURE_OCR.value()) throw new HttpsError("unimplemented", "OCR is not enabled");
```

Client maps `unimplemented` → `.unavailableFeature` → hide, and refreshes flags on next launch. Remote Config conditions (app version, percentage rollout, user property) let you ramp a feature without a server deploy; the server flag is the hard stop.

Do not use Remote Config as the min-version gate — it is fetched lazily, cached for hours, and a build can run for a long time on stale values. The server check is authoritative.

## Deployment order checklist

1. Server change is additive? Deploy server → ship app. Otherwise: new function name → deploy → ship app → schedule retirement.
2. Response gains a required Swift field? Deploy server, confirm in prod logs it is populated, then ship.
3. Enum in a response grows? Confirm the Swift enum has an `unknown` fallback in the *currently shipped* build; if not, the new case is breaking until it does.
4. Retiring a function: check Cloud Logging for calls in the last 30 days (`resource.labels.function_name="createNote"`), raise `MIN_APP_VERSION` above the last build that uses it, wait one release cycle, remove the export, deploy.
5. Tag the server repo with the app version it was verified against.

## Does not exist / common mistakes

- Editing a callable's response shape in place "because the new app is out" — old builds are still installed.
- `createNote_v2` / `createNote.v2` / `v2CreateNote` — the convention is `createNoteV2`.
- Encoding the version in the region or in a query parameter — callables have neither.
- Sending `appVersion` as a header — the `Callable` API does not expose custom headers; put it in the request body.
- Gating with `build` from TestFlight — build numbers are not comparable across release trains.
- Relying on Remote Config for the force-update gate — stale cache; the server `failed-precondition` is the gate.
- Removing an enum case from a response type — old builds without `unknown` crash on decode.

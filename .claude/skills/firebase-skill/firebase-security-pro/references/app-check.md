# App Check

Targets firebase-functions 6.x, firebase-admin 13.x (`firebase-admin/app-check`), Firebase iOS SDK 12.x (`FirebaseAppCheck`).

## What it protects and what it does not

App Check attests that a request comes from **your app binary on a genuine device** (App Attest / DeviceCheck on iOS). The client exchanges an attestation for a short-lived App Check token and attaches it to every Firebase request.

It protects against:

- Scripts, curl, Postman, and scraped API keys calling your callables, Firestore, Storage, RTDB, or Firebase AI Logic directly.
- Cost attacks that hit expensive endpoints from outside the app.
- Replay of a captured request body (only with `consumeAppCheckToken` / limited-use tokens).

It does **not** protect against:

- A legitimate user of your real app doing something they should not. App Check has no notion of *who* — that is Auth.
- A user reading data the rules allow them to read. App Check is not authorization; `allow read: if true` is still public to every app user.
- A jailbroken device running your real binary with a hooked network layer. Treat App Check as raising the bar, not as a guarantee.
- Anything the Admin SDK does — it bypasses App Check like it bypasses rules.

Layer order: App Check → Auth → rules / callable authorization → quota.

## Enforcing on callables

```ts
import { onCall, HttpsError } from "firebase-functions/v2/https";

export const createNote = onCall(
  { region: "asia-southeast1", enforceAppCheck: true },
  async (request) => {
    // request.app is defined here: { appId, token, alreadyConsumed? }
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    return { ok: true };
  },
);
```

- `enforceAppCheck: true` — the callable SDK rejects requests with a missing or invalid App Check token with `unauthenticated` **before** your handler runs. Note the code: App Check failures surface to the iOS client as `FunctionsErrorCode.unauthenticated`, the same code as a missing ID token. Distinguish them by logs, not by client code.
- `enforceAppCheck: false` (default) — `request.app` is populated when a valid token was sent, `undefined` otherwise. Use this for soft rollout: log `request.app === undefined` for a week, then flip to `true`.
- Set it per function or in `setGlobalOptions({ enforceAppCheck: true })` and opt out individually.

## Replay protection: `consumeAppCheckToken` + limited-use tokens

A normal App Check token is valid for its TTL (default 1 hour) and can be reused across requests. For calls where replaying the same request body is itself an attack (purchases, credit spends, one-shot codes), make the token single-use.

Server:

```ts
export const redeemCode = onCall(
  { enforceAppCheck: true, consumeAppCheckToken: true },
  async (request) => {
    // Token has been consumed; a second request with the same token is rejected.
    // request.app.alreadyConsumed is true if the token had been used before (only reachable when consume is false).
  },
);
```

iOS — the client must request a **limited-use** token for that call, otherwise the standard cached token is sent and gets consumed (then every other Firebase call fails until it refreshes):

```swift
import FirebaseFunctions

let functions = Functions.functions(region: "asia-southeast1")
let redeemCode: Callable<RedeemRequest, RedeemResponse> = functions.httpsCallable(
  "redeemCode",
  options: HTTPSCallableOptions(requireLimitedUseAppCheckTokens: true)
)
let result = try await redeemCode(RedeemRequest(code: code))
```

Rules:

- `consumeAppCheckToken: true` implies `enforceAppCheck: true` — set both explicitly for readability.
- Limited-use tokens cost one attestation exchange per call and have a short TTL (5 minutes). Use them for a handful of sensitive callables, not everything.
- Firebase iOS SDK ≥ 10.x is needed for `requireLimitedUseAppCheckTokens`; the bundle targets 12.x.

## Custom verification in `onRequest`

`onRequest` has no `enforceAppCheck`. Read the header and verify:

```ts
import { onRequest } from "firebase-functions/v2/https";
import { getAppCheck } from "firebase-admin/app-check";
import { logger } from "firebase-functions/logger";

export const webhookForApp = onRequest({ region: "asia-southeast1", invoker: "public" }, async (req, res) => {
  const header = req.header("X-Firebase-AppCheck");
  if (!header) { res.status(401).json({ error: "missing-app-check" }); return; }
  try {
    const { appId, alreadyConsumed } = await getAppCheck().verifyToken(header, { consume: true });
    if (alreadyConsumed) { res.status(401).json({ error: "replayed" }); return; }
    logger.debug("app check ok", { appId });
  } catch {
    res.status(401).json({ error: "invalid-app-check" }); return;   // never echo the token
  }
  res.status(200).json({ ok: true });
});
```

iOS attaches the header itself for `URLSession` calls: `let token = try await AppCheck.appCheck().limitedUseToken()` (or `.token(forcingRefresh: false)` for a normal token) → `request.setValue(token.token, forHTTPHeaderField: "X-Firebase-AppCheck")`.

## iOS provider factory

Set the factory **before** `FirebaseApp.configure()`; setting it afterwards is ignored for the default app.

```swift
import FirebaseCore
import FirebaseAppCheck

final class AppCheckFactory: NSObject, AppCheckProviderFactory {
  func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
    #if DEBUG
    return AppCheckDebugProvider(app: app)                        // Simulator, local dev, CI
    #else
    return AppAttestProvider(app: app) ?? DeviceCheckProvider(app: app)   // App Attest needs iOS 14+; fallback to DeviceCheck
    #endif
  }
}

// In App init / AppDelegate, first thing:
AppCheck.setAppCheckProviderFactory(AppCheckFactory())
FirebaseApp.configure()
```

- **App Attest** requires the `App Attest` capability in the entitlements (`com.apple.developer.devicecheck.appattest-environment` = `production` for App Store/TestFlight, `development` for dev builds). Register the app in Firebase console → App Check with the Team ID.
- **DeviceCheck** requires a DeviceCheck private key (.p8) uploaded in the console. Register both providers; the factory falls back automatically.
- `AppAttestProvider(app:)` returns `nil` on unsupported devices/OS; the `??` handles it.
- Do not ship `AppCheckDebugProvider` in a Release build. The `#if DEBUG` guard is mandatory; review it.
- Inside a TCA app the factory setup lives in the app entry point, not in a reducer. Nothing else in the app touches `AppCheck` directly except the `limitedUseToken()` call inside a dependency client.

## Debug tokens for Simulator and CI

The Simulator cannot attest. `AppCheckDebugProvider` prints a debug token to the Xcode console on first launch:

```
[Firebase/AppCheck][I-FAA001001] Firebase App Check debug token: 'A1B2C3D4-…'
```

- Register it in Firebase console → App Check → Apps → ⋮ → Manage debug tokens. Name it per machine/CI runner.
- Pass a fixed token via the launch environment variable `FIRAAppCheckDebugToken` (Scheme → Run → Environment Variables, or `xcodebuild test ... -xctestrun` env) so CI does not generate a new random token each run. Also pass `-FIRDebugEnabled` if you want SDK debug logging.
- Debug tokens are secrets: anyone holding one bypasses App Check for that app. Keep them out of the repo; rotate if leaked; delete tokens of departed machines.
- Never register a debug token for the production Firebase project from a shared laptop. Use the dev project.

Emulator: the Functions emulator does **not** verify App Check tokens; `enforceAppCheck: true` functions accept anything locally. Test enforcement against the dev project, not the emulator.

## Console enforcement for Firestore, Storage, RTDB, Auth

`enforceAppCheck` is a callable/HTTP option only. For the data products, enforcement is a project-level switch: Firebase console → App Check → APIs → Cloud Firestore / Cloud Storage / Realtime Database / Authentication → **Enforce**.

- Before enforcing, watch the metrics tab for **Unverified** requests for a few days; those are older app versions (or attackers). Enforcing breaks every install that does not send a token.
- Authentication enforcement (App Check for Auth) blocks sign-in from outside the app — enable it once every shipped build has App Check.
- There is no `enforceAppCheck` on Firestore triggers, scheduled functions, or task queue functions — those are not client-facing. Flag it as a hallucination if seen.
- Firestore rules cannot inspect App Check. There is no `request.appCheck` in rules. Enforcement is all-or-nothing per product.

## Token TTL

- Default App Check token TTL is 1 hour; configurable per provider in the console (App Attest / DeviceCheck: 30 min – 7 days). Shorter = more attestation calls, faster revocation of a leaked token.
- The SDK auto-refreshes in the background when `isTokenAutoRefreshEnabled` is true (default follows the app's data-collection setting; set `AppCheck.appCheck().isTokenAutoRefreshEnabled = true` explicitly if you disabled analytics collection).
- Limited-use tokens: 5 minutes, never cached.

## Does not exist / common mistakes

- `enforceAppCheck` on `onDocumentCreated`, `onSchedule`, `onTaskDispatched`, `onObjectFinalized` — not an option there; App Check is for client-facing entry points.
- `request.appCheck` in Firestore/Storage rules — does not exist; enforcement is in the console.
- `consumeAppCheckToken: true` without the iOS `requireLimitedUseAppCheckTokens` option — the client's normal cached token gets consumed and the next Firestore/Storage call fails with an App Check error until refresh. Both sides or neither.
- Setting the provider factory after `FirebaseApp.configure()` — silently ignored; the app runs without App Check.
- Assuming App Check rejections surface as `permissionDenied` on iOS — they arrive as `unauthenticated` for callables and as `permission-denied`-style errors for Firestore/Storage. Handle both.
- Treating App Check as a reason to relax rules or skip auth checks — it is an additional layer, never a replacement.
- Testing App Check in the emulator — the emulator does not verify tokens.

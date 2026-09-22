# Error mapping

Three layers, each typed:

1. Server throws `HttpsError(code, message, details)`.
2. SDK delivers an `NSError` with `domain == FunctionsErrorDomain`, `code == FunctionsErrorCode.rawValue`, `userInfo[FunctionsErrorDetailsKey] == details`.
3. Dependency converts to `APIError` (app-level enum + decoded details); reducers switch on `APIError`.

Reducers and views never see `NSError`, `FunctionsErrorCode`, or `localizedDescription`.

## Code mapping table

| `HttpsError` code (TS) | `FunctionsErrorCode` (Swift) | `APIError.Kind` | Retry | UX |
|---|---|---|---|---|
| `invalid-argument` | `.invalidArgument` | `.invalidArgument` | No | Client bug. Log with `details.issues`, show generic error. |
| `unauthenticated` | `.unauthenticated` | `.unauthenticated` | After re-auth | Route to sign-in; keep the draft. Also App Check failure — see below. |
| `permission-denied` | `.permissionDenied` | `.permissionDenied` | No | Explain what is required using `details.reason` (`anonymous`, `role`, `plan`). |
| `not-found` | `.notFound` | `.notFound` | No | Empty state / pop the screen. |
| `already-exists` | `.alreadyExists` | `.alreadyExists` | No | Usually treat as success (idempotent create) or show "already done". |
| `failed-precondition` | `.failedPrecondition` | `.precondition(reason)` | After fixing | `minVersion` → update gate; `emailUnverified` → verify flow; `subscriptionRequired` → paywall. |
| `resource-exhausted` | `.resourceExhausted` | `.quotaExceeded(resetAt)` | After `resetAt` | Paywall or "try again at …". |
| `aborted` | `.aborted` | `.conflict` | Once, immediately | Silent retry once, then show conflict. |
| `out-of-range` | `.outOfRange` | `.invalidArgument` | No | Same as invalid-argument. |
| `unimplemented` | `.unimplemented` | `.unavailableFeature` | No | Hide the feature. |
| `deadline-exceeded` | `.deadlineExceeded` | `.transient` | Backoff | "Taking too long" + retry button. |
| `unavailable` | `.unavailable` | `.transient` | Backoff | Offline banner / retry. |
| `internal` | `.internal` | `.server` | Once | Generic error; log for support. |
| `cancelled` | `.cancelled` | `.cancelled` | — | Ignore (user navigated away). |
| `unknown`, `data-loss` | `.unknown`, `.dataLoss` | `.server` | Once | Generic error. |
| (no Functions domain) | — | `.network` | Backoff | `URLError` — offline, DNS, TLS. |

Keep this table and the server one in `firebase-functions-pro` → `references/errors-and-logging.md` in agreement.

## `details` payload

The server puts a small JSON object in `details`. Define its keys per code, decode leniently:

```swift
struct APIErrorDetails: Decodable, Equatable, Sendable {
  var reason: String?           // permission-denied / failed-precondition discriminator
  var minVersion: String?       // failed-precondition, reason == "appOutdated"
  var limit: Int?               // resource-exhausted
  var resetAt: Date?            // resource-exhausted, ISO-8601
  var retryAfterSeconds: Int?   // unavailable / resource-exhausted
  var field: String?            // invalid-argument (single-field form)
  var issues: [Issue]?          // invalid-argument (zod flatten)

  struct Issue: Decodable, Equatable, Sendable { let path: String; let message: String }
}
```

Server side, the same keys:

```ts
throw new HttpsError("failed-precondition", "App update required", { reason: "appOutdated", minVersion: "2.3.0" });
throw new HttpsError("resource-exhausted", "Daily AI quota reached", { limit: 50, resetAt: resetDate.toISOString() });
throw new HttpsError("permission-denied", "Link an account to share notes", { reason: "anonymous" });
```

All optional on the Swift side; a server that forgets a key must not crash decoding.

## `APIError`

```swift
import FirebaseFunctions
import Foundation

struct APIError: Error, Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case invalidArgument
    case unauthenticated
    case permissionDenied
    case notFound
    case alreadyExists
    case precondition(reason: String?)
    case quotaExceeded(resetAt: Date?)
    case conflict
    case unavailableFeature
    case transient
    case server
    case network
    case cancelled
    case decoding
    case unknown
  }

  let kind: Kind
  let details: APIErrorDetails?
  let debugMessage: String      // server `message` — logs only, never UI

  var isRetryable: Bool {
    switch kind {
    case .transient, .network, .server, .conflict: return true
    default: return false
    }
  }
}

extension APIError {
  static let unknown = APIError(kind: .unknown, details: nil, debugMessage: "")

  init(_ error: any Error) {
    if error is CancellationError { self.init(kind: .cancelled, details: nil, debugMessage: "cancelled"); return }
    if error is DecodingError { self.init(kind: .decoding, details: nil, debugMessage: String(describing: error)); return }

    let ns = error as NSError
    guard ns.domain == FunctionsErrorDomain, let code = FunctionsErrorCode(rawValue: ns.code) else {
      if ns.domain == NSURLErrorDomain { self.init(kind: .network, details: nil, debugMessage: ns.localizedDescription); return }
      self.init(kind: .unknown, details: nil, debugMessage: ns.localizedDescription); return
    }

    let details = Self.decodeDetails(ns.userInfo[FunctionsErrorDetailsKey])
    let kind: Kind
    switch code {
    case .invalidArgument, .outOfRange: kind = .invalidArgument
    case .unauthenticated:              kind = .unauthenticated
    case .permissionDenied:             kind = .permissionDenied
    case .notFound:                     kind = .notFound
    case .alreadyExists:                kind = .alreadyExists
    case .failedPrecondition:           kind = .precondition(reason: details?.reason)
    case .resourceExhausted:            kind = .quotaExceeded(resetAt: details?.resetAt)
    case .aborted:                      kind = .conflict
    case .unimplemented:                kind = .unavailableFeature
    case .deadlineExceeded, .unavailable: kind = .transient
    case .cancelled:                    kind = .cancelled
    case .internal, .unknown, .dataLoss: kind = .server
    case .OK:                           kind = .unknown
    @unknown default:                   kind = .unknown
    }
    self.init(kind: kind, details: details, debugMessage: ns.localizedDescription)
  }

  private static func decodeDetails(_ raw: Any?) -> APIErrorDetails? {
    guard let raw, JSONSerialization.isValidJSONObject(raw),
          let data = try? JSONSerialization.data(withJSONObject: raw)
    else { return nil }
    return try? FirebaseJSON.jsonDecoder.decode(APIErrorDetails.self, from: data)
  }
}
```

- `FunctionsErrorCode` is an `@objc` enum; `FunctionsErrorCode(rawValue:)` is the documented way to recover it from `NSError.code`. The `.OK` case exists (raw 0) and never arrives as an error. Include `@unknown default`.
- `details` arrives as `Any` (`NSDictionary`/`NSArray`/`NSString`/`NSNumber`). Round-trip through `JSONSerialization` to decode with a plain `JSONDecoder` (`FirebaseJSON.jsonDecoder`, same date strategy as the callable decoder).
- Wrap the conversion at the dependency boundary: `catch { throw APIError(error) }`. Do it in one place per client, not per call site.

## Retry policy

Implement once, in the dependency or an `Effect` helper, never ad hoc in reducers:

```swift
func withRetry<T: Sendable>(
  maxAttempts: Int = 3,
  clock: any Clock<Duration>,
  _ operation: @Sendable () async throws -> T
) async throws -> T {
  var attempt = 0
  while true {
    do { return try await operation() }
    catch let error as APIError where error.isRetryable && attempt < maxAttempts - 1 {
      attempt += 1
      let base = error.details?.retryAfterSeconds.map { Double($0) } ?? pow(2, Double(attempt)) * 0.5
      try await clock.sleep(for: .seconds(base + .random(in: 0...0.3)))
    }
  }
}
```

- `.conflict` (`aborted`): retry once, immediately — the server transaction already retried; a second client attempt usually succeeds.
- `.transient` / `.network`: exponential backoff with jitter, cap 3 attempts, honour `retryAfterSeconds`.
- `.server` (`internal`): retry once. If it fails twice it is a bug, not weather.
- Never retry `.invalidArgument`, `.permissionDenied`, `.notFound`, `.alreadyExists`, `.precondition`, `.quotaExceeded` (before `resetAt`), `.unauthenticated` (until re-auth).
- Non-idempotent callables (`createNote` without a client-supplied id) must not auto-retry `.transient` after the request may have reached the server. Either make them idempotent (client generates `noteId`, server uses `ref.create()`) or retry only `.network` errors that failed before send. When in doubt, generate the id on the client.
- Use the TCA `@Dependency(\.continuousClock)` for the sleep so tests run instantly (`tca-pro` → `references/testing.md`).

## `unauthenticated` vs `permission-denied`

| | `unauthenticated` | `permission-denied` |
|---|---|---|
| Server meaning | Do not know who you are: no token, expired, revoked, or App Check failed | Know who you are; you may not do this |
| Typical cause | Signed out, token refresh failed, App Check debug token missing, `consumeAppCheckToken` replay | Anonymous where permanent required, missing custom claim, not the owner, plan too low |
| UX | Present sign-in (or re-auth) and preserve the in-progress state; retry after success | Explain and offer the fix: link account, upgrade, request access. No retry button. |
| Reducer action | `.delegate(.signInRequired)` bubbled to the root | Alert / inline message driven by `details.reason` |
| Log level | info (expected) | info (expected) |

App Check failures also surface as `unauthenticated` on callables with `enforceAppCheck`. In DEBUG, if every call fails with `unauthenticated` while the user is signed in, check the App Check debug token before anything else.

Server rule that keeps the client simple: check auth first, then validate, then authorise. That way a signed-out user with a malformed payload sees `unauthenticated`, not `invalid-argument`, and lands on sign-in.

## Presenting errors

```swift
extension APIError.Kind {
  var userMessage: LocalizedStringResource {
    switch self {
    case .transient, .network: "Connection problem. Please try again."
    case .quotaExceeded(let resetAt):
      resetAt.map { "Daily limit reached. Try again \($0.formatted(.relative(presentation: .named)))." }
        ?? "Daily limit reached."
    case .precondition(let reason) where reason == "appOutdated": "Please update the app to continue."
    case .permissionDenied: "You do not have access to this."
    case .notFound: "This item no longer exists."
    case .unauthenticated: "Please sign in to continue."
    default: "Something went wrong."
    }
  }
}
```

- Copy is keyed on `kind` (+ `details.reason`), localised in the app. The server `message` is English developer text.
- Log `debugMessage` and `details` with the analytics/crash dependency at the point of failure, not from the view.

## Testing the mapping

```swift
@Test func mapsFailedPreconditionWithMinVersion() {
  let ns = NSError(
    domain: FunctionsErrorDomain,
    code: FunctionsErrorCode.failedPrecondition.rawValue,
    userInfo: [FunctionsErrorDetailsKey: ["reason": "appOutdated", "minVersion": "2.3.0"]]
  )
  let error = APIError(ns)
  #expect(error.kind == .precondition(reason: "appOutdated"))
  #expect(error.details?.minVersion == "2.3.0")
}
```

Build `NSError`s by hand this way in unit tests; no Firebase network needed.

## Does not exist / common mistakes

- `catch let error as FunctionsError` — there is no such Swift error type; it is `NSError` in `FunctionsErrorDomain`.
- `error.code as? FunctionsErrorCode` — `code` is `Int`; use `FunctionsErrorCode(rawValue:)`.
- `error.userInfo["details"]` — the key is the constant `FunctionsErrorDetailsKey`.
- Switching on `error.localizedDescription` strings — brittle; switch on the code.
- Treating every error as retryable — retries `invalid-argument` forever and double-creates on `internal`.
- Showing `error.localizedDescription` (the server `message`) in an alert — untranslated developer text, sometimes with internals.
- Mapping `permission-denied` to the sign-in screen — the user is signed in; they need a different fix.
- Decoding `details` with `as! [String: String]` — values are mixed types (`Int`, arrays); decode through `JSONSerialization` + `Decodable`.

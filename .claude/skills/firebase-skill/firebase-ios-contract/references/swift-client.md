# Swift client

Firebase iOS SDK 12.x, `FirebaseFunctions` module. Everything here lives inside a dependency's `liveValue` (see `tca-integration.md`); no view or reducer imports `FirebaseFunctions`.

## Setup order

```swift
// App entry — before anything touches Firebase
import FirebaseCore
import FirebaseAppCheck

AppCheck.setAppCheckProviderFactory(AppCheckFactory())   // must precede configure()
FirebaseApp.configure()
```

`Functions.functions(...)` after `configure()`. Creating it before crashes with "Default app has not been configured".

## Getting a `Functions` instance

```swift
import FirebaseFunctions

let functions = Functions.functions(region: "asia-southeast1")
```

- Region must match `setGlobalOptions({ region })` on the server. Default without the argument is `us-central1`; a mismatch is a runtime `not-found` on every call.
- `Functions.functions(region:)` returns a cached instance per (app, region); calling it repeatedly is fine, but hold one reference in the dependency anyway.
- Custom domain (`Functions.functions(customDomain:)`) is for Hosting rewrites; not used with plain callables.

### Emulator

```swift
#if DEBUG
if ProcessInfo.processInfo.environment["USE_FIREBASE_EMULATOR"] == "1" {
  functions.useEmulator(withHost: "127.0.0.1", port: 5001)
}
#endif
```

- Call once, before the first `httpsCallable`. Calling it after a request has been made has no effect on the in-flight configuration.
- Physical device: use the Mac's LAN IP and set `"host": "0.0.0.0"` under `emulators.functions` in `firebase.json`.
- Also point Auth/Firestore/Storage at their emulators in the same block, or the callable's ID token comes from prod Auth and the emulator's `request.auth` is still populated (the emulator accepts prod tokens without verification) but Firestore writes land in prod.
- Gate on an environment variable or a launch argument set in the scheme, not on `#if DEBUG` alone — you want DEBUG builds that hit the dev project too.

## Typed callable: `Callable<Request, Response>`

Requires Firebase iOS SDK ≥ 10.x for `Callable`, ≥ 11.8 for `stream()`.

```swift
struct CreateNoteRequest: Codable, Equatable, Sendable {
  var title: String
  var body: String = ""
  var tags: [String] = []
}

struct CreateNoteResponse: Codable, Equatable, Sendable {
  let id: String
  let createdAt: Date
}

let createNote: Callable<CreateNoteRequest, CreateNoteResponse> = functions.httpsCallable(
  "createNote",
  requestAs: CreateNoteRequest.self,
  responseAs: CreateNoteResponse.self,
  encoder: FirebaseJSON.encoder,
  decoder: FirebaseJSON.decoder
)

// callAsFunction — the idiomatic call site
let response = try await createNote(CreateNoteRequest(title: "Hi"))

// equivalent
let response2 = try await createNote.call(CreateNoteRequest(title: "Hi"))
```

- Generic inference also works: `let createNote: Callable<CreateNoteRequest, CreateNoteResponse> = functions.httpsCallable("createNote")`. Pass `requestAs:responseAs:` when the types are not obvious at the declaration.
- `Callable` is a value; store one per operation in the dependency's `liveValue` closure capture. Creating it per call is cheap but pointless.
- `createNote.timeoutInterval` (default 70 s) is the client-side deadline. Raise it for functions whose `timeoutSeconds` exceeds 70, and lower it for CRUD callables so a dead network fails fast (`15`).

### Encoder / decoder

The `encoder:` / `decoder:` parameters are `FirebaseDataEncoder` / `FirebaseDataDecoder` (from the `FirebaseSharedSwift` module, re-exported by `FirebaseFunctions` — verify the import against firebase docs for your SDK version). They mirror `JSONEncoder`/`JSONDecoder` strategies. Define them once:

```swift
import FirebaseSharedSwift

enum FirebaseJSON {
  static let encoder: FirebaseDataEncoder = {
    let e = FirebaseDataEncoder()
    e.dateEncodingStrategy = .custom { date, encoder in
      var c = encoder.singleValueContainer()
      try c.encode(iso8601Fractional.string(from: date))
    }
    return e
  }()

  static let decoder: FirebaseDataDecoder = {
    let d = FirebaseDataDecoder()
    d.dateDecodingStrategy = .custom { decoder in
      let raw = try decoder.singleValueContainer().decode(String.self)
      if let date = iso8601Fractional.date(from: raw) ?? iso8601Plain.date(from: raw) { return date }
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad ISO-8601 date: \(raw)"))
    }
    return d
  }()

  /// Plain JSONDecoder with the same date rule — for decoding `HttpsError.details` and Firestore-listener payloads.
  static let jsonDecoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .custom { decoder in
      let raw = try decoder.singleValueContainer().decode(String.self)
      if let date = iso8601Fractional.date(from: raw) ?? iso8601Plain.date(from: raw) { return date }
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad ISO-8601 date: \(raw)"))
    }
    return d
  }()

  private static let iso8601Fractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()
  private static let iso8601Plain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
  }()
}
```

Why custom: `.iso8601` alone rejects fractional seconds, and `Date.prototype.toISOString()` always emits them. Accepting both keeps the client tolerant of a server that switches to second precision.

Do not set `keyDecodingStrategy = .convertFromSnakeCase`. The contract is camelCase on both sides; a snake_case field is a server bug to fix, not a decoder setting to hide.

## Untyped callable (avoid)

```swift
let result = try await functions.httpsCallable("createNote").call(["title": "Hi"])
let dict = result.data as? [String: Any]
```

`HTTPSCallableResult.data` is `Any`. Use only for exploratory calls or when a payload genuinely has no schema. Everything in the app contract is `Callable<Req, Res>`.

## Streaming

Server side: a callable that calls `response.sendChunk(chunk)` and returns a final value (`firebase-functions-pro` → `references/callable.md`). Client side needs iOS SDK ≥ 11.8.

```swift
struct ChatRequest: Codable, Sendable { let prompt: String }
struct ChatChunk: Codable, Sendable { let text: String }        // shape of each sendChunk
struct ChatResponse: Codable, Sendable { let text: String }     // shape of the return value

let chat: Callable<ChatRequest, StreamResponse<ChatChunk, ChatResponse>> = functions.httpsCallable("chat")
chat.timeoutInterval = 180

func streamChat(_ prompt: String) -> AsyncThrowingStream<ChatEvent, Error> {
  AsyncThrowingStream { continuation in
    let task = Task {
      do {
        for try await item in try chat.stream(ChatRequest(prompt: prompt)) {
          switch item {
          case .message(let chunk): continuation.yield(.delta(chunk.text))
          case .result(let final): continuation.yield(.completed(final.text))
          }
        }
        continuation.finish()
      } catch {
        continuation.finish(throwing: APIError(error))
      }
    }
    continuation.onTermination = { _ in task.cancel() }
  }
}
```

- `StreamResponse<Message, Result>` has two generic parameters: the chunk type and the final type. Verify the exact generic arity against firebase docs for the pinned SDK; the fact sheet's shorthand `StreamResponse<Response>` refers to this type.
- `.result` arrives exactly once, last. If the server throws after sending chunks, the `for try await` throws and `.result` never arrives — handle partial output in the reducer (keep what was streamed, show the error).
- Cancelling the consuming `Task` cancels the underlying request. Wire it to `.cancellable(id:)` in the effect so leaving the screen stops the stream (see `tca-integration.md`).
- `stream()` uses server-sent events over the same HTTPS callable URL; no extra server config. Under the emulator it works the same way.
- The non-streaming `call` on the same function returns only the final value — the server must `return` it regardless of `acceptsStreaming`.

## App Check

Default: every callable sends the current App Check token automatically once a provider factory is set. With `enforceAppCheck: true` on the server, a missing or invalid token fails with `unauthenticated` before the handler runs.

Replay-protected calls (server sets `consumeAppCheckToken: true`):

```swift
let redeemCode: Callable<RedeemCodeRequest, RedeemCodeResponse> = functions.httpsCallable(
  "redeemCode",
  options: HTTPSCallableOptions(requireLimitedUseAppCheckTokens: true),
  requestAs: RedeemCodeRequest.self,
  responseAs: RedeemCodeResponse.self,
  encoder: FirebaseJSON.encoder,
  decoder: FirebaseJSON.decoder
)
```

- Limited-use tokens are single-use and fetched per call (extra round trip to the App Check backend). Use only for purchases, redemptions, account deletion — not for reads.
- Mismatch either way is a bug: server consumes + client sends normal tokens → second call fails; client sends limited-use + server does not consume → wasted round trip, still works.
- DEBUG builds use `AppCheckDebugProvider` and a debug token registered in the console; without that, `enforceAppCheck` rejects every simulator call. The emulator does not enforce App Check.

## Auth token behaviour

- The SDK attaches the current user's ID token automatically and refreshes it when expired. You do not pass it.
- After the server calls `setCustomUserClaims`, the client must `try await Auth.auth().currentUser?.getIDTokenResult(forcingRefresh: true)` before the next callable sees the new claim.
- Signed-out user: the call goes out without a token; the server sees `request.auth == nil` and should throw `unauthenticated`. Do not pre-check `Auth.auth().currentUser` in the dependency and throw locally — the server is the source of truth and the UX path is the same.

## Cancellation and timeouts

- `try await callable(request)` is cancellable via Swift task cancellation; the SDK cancels the URL task. A cancelled call throws `CancellationError` or an `NSError` with `FunctionsErrorCode.cancelled`; treat both as "ignore".
- `timeoutInterval` on the `Callable` is per-call-site. A server `timeoutSeconds: 120` with a client default of 70 s means the client gives up first with `deadlineExceeded`.

## Error surface

Every failure is an `NSError` with `domain == FunctionsErrorDomain`. Decode it once in the dependency and throw a typed app error; see `error-mapping.md`. Never let a raw `NSError` reach a reducer.

## Does not exist / common mistakes

- `Functions.functions()` without region while the server is in `asia-southeast1` — `not-found` at runtime.
- `functions.httpsCallable("x").call(data)` decoded via `result.data as? MyStruct` — `data` is `Any`, not Codable. Use `Callable<Req, Res>`.
- `JSONDecoder` passed as `decoder:` — the parameter is `FirebaseDataDecoder`.
- `.iso8601` date strategy — rejects the fractional seconds `toISOString()` emits.
- `useEmulator` after the first call, or outside the same code path that creates `Functions` — silently ignored or inconsistent.
- `Callable<Req, Res>.stream()` when `Res` is not a `StreamResponse` — will not compile; the response generic must be the `StreamResponse` type.
- `HTTPSCallableOptions(requireLimitedUseAppCheckTokens: true)` on every callable "for safety" — doubles latency and can exhaust App Check quota.
- Reading `Auth.auth().currentUser?.uid` and sending it as a request field — the server ignores or, worse, trusts it.

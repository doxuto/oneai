---
name: firebase-ios-contract
description: Writes, reviews, and keeps in sync the API contract between Firebase Cloud Functions (TypeScript, onCall) and the Swift/SwiftUI/TCA iOS client that calls them. Use when reading, writing, or reviewing code that uses Callable<Request, Response>, httpsCallable, FirebaseFunctions, FunctionsErrorCode, FunctionsErrorDomain, FunctionsErrorDetailsKey, StreamResponse, useEmulator, HTTPSCallableOptions, Codable request/response structs mirroring a zod schema, a @DependencyClient wrapping Firebase Functions for TCA, or when the user mentions API contract, envelope, versioning a callable, streaming from iOS, or error mapping between HttpsError and the app.
license: MIT
metadata:
  author: doxuto
  version: "1.0"
  targets: "firebase-functions 6.x (v2), firebase-admin 13.x, Node 22, Firebase iOS SDK 12.x"
---

Define and review the request/response contract between `onCall` functions and the Swift client so that both sides compile against the same shape, errors map to app-level cases, and changes ship without breaking installed builds. Report only genuine problems — do not nitpick or invent issues.

## Core principles

1. **One shape, two languages.** The zod schema on the server and the `Codable` struct on iOS describe the same JSON. Field names, optionality, and enum cases are identical; only the syntax differs.
2. **JSON on the wire, nothing else.** Strings, numbers, booleans, null, arrays, objects. Dates are ISO-8601 strings. Firestore `Timestamp`, `DocumentReference`, and `GeoPoint` never cross the callable boundary.
3. **Errors are typed on both sides.** Every `HttpsError` code the server throws has a corresponding `FunctionsErrorCode` case the client switches on, then maps to an app-level error enum with a retry policy and a UX decision.
4. **Additive evolution only.** A shipped iOS build calls the deployed function name with the deployed shape. Add optional fields; never rename, remove, or change types in place. Breaking changes get a new function name.
5. **The client talks to a dependency, not to Firebase.** Reducers call a `@DependencyClient`; only its `liveValue` knows about `Functions`. Tests use `testValue` overrides. See `tca-pro`.
6. **Request/response for answers, listeners for progress.** A callable returns within seconds. Anything longer writes a status document and the client observes it with a Firestore listener.

## Review process

1. Check function naming, envelope shape, field naming, dates, enums, optionals, and pagination cursors using `references/envelope-and-naming.md`.
2. Check the Swift `Callable<Req, Res>` setup, region, emulator wiring, decoding, streaming, and App Check options using `references/swift-client.md`.
3. Check error propagation from `HttpsError` through `FunctionsErrorCode` to the app error enum, `details` decoding, and retry policy using `references/error-mapping.md`.
4. Check the `@DependencyClient` wrapper, `liveValue`/`testValue`, effect usage, cancellation, and `TestStore` coverage using `references/tca-integration.md`.
5. Check every contract change for backward compatibility, versioned function names, deprecations, and the minimum-version gate using `references/versioning.md`.
6. Check that the zod schema and the Codable struct agree field by field using `references/shared-types.md`.
7. Check that long-running or progressive work uses a status document + listener, not a long callable or polling, using `references/realtime-vs-callable.md`.

If doing a partial review, load only the relevant reference files.

## Core instructions

- Target Firebase iOS SDK 12.x, Swift 6.2, TCA 1.26+, firebase-functions 6.x. `Callable<Request, Response>` and `.stream(_:)` need iOS SDK ≥ 11.8; do not offer them to older pins.
- Function names are camelCase verbs from the client's point of view (`createNote`, `redeemCode`), identical in `export const`, in the barrel, and in `httpsCallable("createNote")`. No `domain.verb` dots — dots are not valid deployed names.
- Every request and response is a named struct on both sides: `CreateNoteRequest` / `CreateNoteResponse` in Swift, `CreateNoteInput` / `CreateNoteOutput` in TS. No `[String: Any]`, no `Any` decoding, no positional arrays.
- Field names are camelCase on both sides; no `CodingKeys` remapping unless wrapping a third-party payload. Dates are ISO-8601 strings with fractional seconds and `Z`; decode with a custom `JSONDecoder.dateDecodingStrategy` that accepts both `.iso8601` and fractional seconds.
- Enums cross the wire as string literals: `z.enum([...])` ↔ `enum X: String, Codable`. Add an `unknown` fallback on the Swift side when the server may add cases before the app updates.
- Optional in the schema means optional in Swift (`String?`), and vice versa. A field with a zod `.default()` is required in the output type and non-optional in the Swift response.
- Region is set once: `Functions.functions(region: "asia-southeast1")` inside the dependency's `liveValue`, matching `setGlobalOptions`. `useEmulator(withHost:port:)` only under `#if DEBUG` and only before the first call.
- Catch `NSError` with `error.domain == FunctionsErrorDomain`, read `FunctionsErrorCode(rawValue: error.code)`, decode `error.userInfo[FunctionsErrorDetailsKey]` into a typed `ErrorDetails`, then map to the app error enum. Never show `error.localizedDescription` to a user.
- `unauthenticated` routes to sign-in; `permission-denied` explains what is missing; `failed-precondition` with `details.minVersion` shows the update gate; `unavailable`/`deadline-exceeded`/`internal` retry with backoff once; `invalid-argument` is a client bug and is logged, not retried.
- Reducers never import `FirebaseFunctions`. They call `@Dependency(\.notesClient)` from an `Effect.run`, wrap the result in `Result`, and send it back as an action. Cancel with `.cancellable(id:)` when the screen can be left.
- Changing a response field's type, removing a field, or making an optional required is a breaking change: ship it as `createNoteV2` and keep `createNote` until the old build is retired.
- For any operation that takes longer than ~10 s or reports progress, the callable enqueues work and returns a job id; the client listens to `users/{uid}/jobs/{jobId}` via a Firestore listener wrapped in an `AsyncStream` dependency.

## Canonical example

Server — `functions/src/notes/createNote.ts` (see `firebase-functions-pro` for the surrounding project):

```ts
import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { FieldValue } from "firebase-admin/firestore";
import { z } from "zod";
import { db } from "../lib/admin.js";
import { parse } from "../lib/validate.js";

export const NoteVisibility = z.enum(["private", "shared"]);

export const CreateNoteInput = z.object({
  title: z.string().min(1).max(200),
  body: z.string().max(20_000).default(""),
  visibility: NoteVisibility.default("private"),
  tags: z.array(z.string().min(1).max(30)).max(10).default([]),
});

export interface CreateNoteOutput {
  id: string;
  title: string;
  visibility: z.infer<typeof NoteVisibility>;
  createdAt: string;   // ISO-8601
  tags: string[];
}

export const createNote = onCall(
  { enforceAppCheck: true, timeoutSeconds: 30 },
  async (request: CallableRequest<unknown>): Promise<CreateNoteOutput> => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required");
    const uid = request.auth.uid;
    const input = parse(CreateNoteInput, request.data);

    const ref = db.collection(`users/${uid}/notes`).doc();
    const now = new Date();
    await ref.set({ ...input, createdAt: FieldValue.serverTimestamp(), updatedAt: FieldValue.serverTimestamp() });

    return { id: ref.id, title: input.title, visibility: input.visibility, createdAt: now.toISOString(), tags: input.tags };
  },
);
```

Client — `NotesAPI.swift` (Codable mirror + TCA dependency):

```swift
import ComposableArchitecture
import FirebaseFunctions
import Foundation

// MARK: - Contract (mirrors CreateNoteInput / CreateNoteOutput)

enum NoteVisibility: String, Codable, Equatable, Sendable {
  case `private`, shared
}

struct CreateNoteRequest: Codable, Equatable, Sendable {
  var title: String
  var body: String = ""
  var visibility: NoteVisibility = .private
  var tags: [String] = []
}

struct CreateNoteResponse: Codable, Equatable, Sendable {
  let id: String
  let title: String
  let visibility: NoteVisibility
  let createdAt: Date        // decoded from ISO-8601 via the shared decoder
  let tags: [String]
}

// MARK: - Dependency

@DependencyClient
struct NotesClient: Sendable {
  var createNote: @Sendable (CreateNoteRequest) async throws -> CreateNoteResponse
}

extension NotesClient: DependencyKey {
  static let liveValue: NotesClient = {
    let functions = Functions.functions(region: "asia-southeast1")
    #if DEBUG
    if ProcessInfo.processInfo.environment["USE_FIREBASE_EMULATOR"] == "1" {
      functions.useEmulator(withHost: "127.0.0.1", port: 5001)
    }
    #endif
    let createNote: Callable<CreateNoteRequest, CreateNoteResponse> = functions.httpsCallable(
      "createNote",
      requestAs: CreateNoteRequest.self,
      responseAs: CreateNoteResponse.self,
      decoder: FirebaseJSON.decoder
    )
    return NotesClient(
      createNote: { request in
        do { return try await createNote(request) }
        catch { throw APIError(error) }   // see references/error-mapping.md
      }
    )
  }()

  static let testValue = NotesClient()   // @DependencyClient supplies unimplemented stubs
}

extension DependencyValues {
  var notesClient: NotesClient {
    get { self[NotesClient.self] }
    set { self[NotesClient.self] = newValue }
  }
}
```

Reducer usage (`tca-pro` conventions):

```swift
case .saveButtonTapped:
  state.isSaving = true
  return .run { [draft = state.draft] send in
    await send(.createNoteResponse(Result { try await notesClient.createNote(draft) }))
  }
  .cancellable(id: CancelID.save, cancelInFlight: true)

case let .createNoteResponse(.failure(error as APIError)) where error.kind == .unauthenticated:
  state.isSaving = false
  return .send(.delegate(.signInRequired))
```

## Output format

If the user asks for a review, organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated.
3. Show a brief before/after code fix.

Skip files with no issues. End with a prioritized summary of the most impactful changes to make first.

If the user asks you to write or improve code, follow the same rules but make the changes directly instead of returning a findings report.

Example output:

### functions/src/notes/getNote.ts

**Line 22: Firestore `Timestamp` returned in the callable response — the Swift `Date` decoder fails and the whole response is lost.**

```ts
// Before
return { id: snap.id, ...snap.data() };

// After
const d = snap.data()!;
return { id: snap.id, title: d.title, createdAt: (d.createdAt as Timestamp).toDate().toISOString() };
```

### NotesClient.swift

**Line 41: `error.localizedDescription` surfaced to the alert — leaks the server developer message and cannot be localised or switched on.**

```swift
// Before
state.alert = AlertState { TextState(error.localizedDescription) }

// After
let apiError = error as? APIError ?? .unknown
state.alert = AlertState { TextState(apiError.userMessage) }
```

### Summary

1. **Contract break (high):** `getNote` returns a `Timestamp`; every call fails to decode on iOS.
2. **UX / localisation (medium):** Raw error strings in the alert on line 41.

End of example.

## References

- `references/envelope-and-naming.md` — function naming, request/response envelope conventions, camelCase, ISO-8601 dates, no `Timestamp` over the wire, optionals, enums as strings, pagination cursor shape.
- `references/swift-client.md` — `Callable<Req, Res>`, `callAsFunction`, region, `useEmulator` in DEBUG, JSON decoding setup, `stream()` and `StreamResponse`, limited-use App Check tokens.
- `references/error-mapping.md` — `HttpsError` code → `FunctionsErrorCode` → app-level error enum, decoding `details`, retry policy per code, `unauthenticated` vs `permission-denied` UX.
- `references/tca-integration.md` — `@DependencyClient` wrapping callables, `liveValue`/`testValue`, calling from an effect, cancellation, a `TestStore` example; defers to `tca-pro` for the architecture.
- `references/versioning.md` — additive changes, `V2` suffix functions, deprecating fields, minimum app version gate via `failed-precondition` + `details.minVersion`, feature flags via Remote Config.
- `references/shared-types.md` — zod schema ↔ Codable struct side by side, optional codegen via `zod-to-json-schema` + quicktype, keeping one source of truth.
- `references/realtime-vs-callable.md` — when to use a Firestore listener instead of a callable, the task queue + status document pattern, and the client-side `AsyncStream` listener dependency.

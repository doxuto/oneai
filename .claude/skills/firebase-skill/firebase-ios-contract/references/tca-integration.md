# TCA integration

The architecture rules — `@Reducer`, effects, `@Dependency`, `TestStore` — are in `tca-pro` (`references/dependencies.md`, `references/effects.md`, `references/testing.md`). This file covers only what is specific to wrapping Firebase callables. Do not restate `tca-pro` here; link to it.

## Shape of a Functions dependency

One `@DependencyClient` per domain (`NotesClient`, `BillingClient`, `AIClient`), not one giant `FirebaseClient`. Each closure is one callable. Request and response types are the contract structs from `envelope-and-naming.md`.

```swift
import ComposableArchitecture
import Foundation

@DependencyClient
struct NotesClient: Sendable {
  var createNote: @Sendable (CreateNoteRequest) async throws -> CreateNoteResponse
  var listNotes: @Sendable (ListNotesRequest) async throws -> ListNotesResponse
  var deleteNote: @Sendable (DeleteNoteRequest) async throws -> Void
}

extension DependencyValues {
  var notesClient: NotesClient {
    get { self[NotesClient.self] }
    set { self[NotesClient.self] = newValue }
  }
}
```

- Closures take the request struct, not loose parameters. One argument keeps the `@DependencyClient` stubs simple and the contract visible.
- Every closure `throws`. The thrown type is always `APIError` (from `error-mapping.md`); the live value converts at the boundary.
- `Void`-returning callables (`deleteNote`) still call a `Callable<DeleteNoteRequest, EmptyResponse>` inside and discard the result.

## `liveValue`

```swift
import FirebaseFunctions

extension NotesClient: DependencyKey {
  static let liveValue: NotesClient = {
    let functions = FirebaseFunctionsFactory.shared   // one configured instance for all clients

    let createNote: Callable<CreateNoteRequest, CreateNoteResponse> =
      functions.httpsCallable(FunctionName.createNote, encoder: FirebaseJSON.encoder, decoder: FirebaseJSON.decoder)
    let listNotes: Callable<ListNotesRequest, ListNotesResponse> =
      functions.httpsCallable(FunctionName.listNotes, encoder: FirebaseJSON.encoder, decoder: FirebaseJSON.decoder)
    let deleteNote: Callable<DeleteNoteRequest, EmptyResponse> =
      functions.httpsCallable(FunctionName.deleteNote, encoder: FirebaseJSON.encoder, decoder: FirebaseJSON.decoder)

    return NotesClient(
      createNote: { try await mapping { try await createNote($0) } },
      listNotes: { try await mapping { try await listNotes($0) } },
      deleteNote: { _ = try await mapping { try await deleteNote($0) } }
    )
  }()
}

/// Converts any thrown error to APIError exactly once, at the dependency boundary.
@Sendable
private func mapping<T: Sendable>(_ op: @Sendable () async throws -> T) async throws -> T {
  do { return try await op() }
  catch { throw APIError(error) }
}

enum FirebaseFunctionsFactory {
  static let shared: Functions = {
    let f = Functions.functions(region: "asia-southeast1")
    #if DEBUG
    if ProcessInfo.processInfo.environment["USE_FIREBASE_EMULATOR"] == "1" {
      f.useEmulator(withHost: "127.0.0.1", port: 5001)
    }
    #endif
    return f
  }()
}
```

- `Functions` configuration (region, emulator) is in one factory shared by every domain client so the emulator switch is not repeated.
- `FirebaseFunctions` is imported only in `liveValue` files. Put each live value in its own file (`NotesClient+Live.swift`) so the interface file compiles without Firebase — this matters for a `Contract` SwiftPM module shared with tests and previews.

## `testValue` and `previewValue`

`@DependencyClient` generates `testValue` with unimplemented closures that fail the test if called unexpectedly (`tca-pro` → `references/dependencies.md`). Do not write a hand-rolled `testValue`. For previews, supply canned data:

```swift
extension NotesClient {
  static let previewValue = NotesClient(
    createNote: { req in CreateNoteResponse(id: "preview", title: req.title, visibility: req.visibility, createdAt: .now, tags: req.tags) },
    listNotes: { _ in ListNotesResponse(items: NoteSummary.mocks, nextCursor: nil) },
    deleteNote: { _ in }
  )
}
```

## Calling from a reducer

```swift
@Reducer
struct NoteEditor {
  @ObservableState
  struct State: Equatable {
    var draft = CreateNoteRequest(title: "")
    var isSaving = false
    @Presents var alert: AlertState<Action.Alert>?
  }

  enum Action {
    case alert(PresentationAction<Alert>)
    case saveButtonTapped
    case createNoteResponse(Result<CreateNoteResponse, APIError>)
    case delegate(Delegate)

    @CasePathable enum Alert: Equatable { case retryButtonTapped }
    @CasePathable enum Delegate: Equatable { case saved(CreateNoteResponse); case signInRequired }
  }

  @Dependency(\.notesClient) var notesClient
  @Dependency(\.dismiss) var dismiss

  private enum CancelID { case save }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .saveButtonTapped:
        return save(state: &state)

      case let .createNoteResponse(.success(response)):
        state.isSaving = false
        return .send(.delegate(.saved(response)))

      case let .createNoteResponse(.failure(error)):
        state.isSaving = false
        switch error.kind {
        case .unauthenticated:
          return .send(.delegate(.signInRequired))
        case .cancelled:
          return .none
        case .invalidArgument:
          state.alert = AlertState { TextState(error.kind.userMessage) }
          return .none
        default:
          state.alert = AlertState {
            TextState(error.kind.userMessage)
          } actions: {
            ButtonState(role: .cancel) { TextState("OK") }
            if error.isRetryable { ButtonState(action: .retryButtonTapped) { TextState("Retry") } }
          }
          return .none
        }

      case .alert(.presented(.retryButtonTapped)):
        return save(state: &state)

      case .alert, .delegate:
        return .none
      }
    }
    .ifLet(\.$alert, action: \.alert)
  }

  private func save(state: inout State) -> Effect<Action> {
    state.isSaving = true
    return .run { [draft = state.draft] send in
      await send(.createNoteResponse(
        Result { try await notesClient.createNote(draft) }.mapError { $0 as? APIError ?? .unknown }
      ))
    }
    .cancellable(id: CancelID.save, cancelInFlight: true)
  }
}
```

- The response action carries `Result<Response, APIError>`, not `Result<Response, any Error>`. `APIError` is `Equatable`, so `TestStore` can assert on it exactly.
- `.cancellable(id:cancelInFlight:)` on every callable effect: double taps cancel the first request; leaving the screen (parent runs `.cancel(id:)` or the store is deallocated) cancels the URL task.
- `.unauthenticated` bubbles up as a delegate action; the root feature owns sign-in.
- Do not call `notesClient` outside `.run`. No `Task {}` in the reducer, no calls from the view.

## Streaming in a reducer

```swift
case .sendButtonTapped:
  state.reply = ""
  state.isStreaming = true
  return .run { [prompt = state.prompt] send in
    do {
      for try await event in aiClient.chat(ChatRequest(prompt: prompt)) {
        await send(.chatEvent(event))
      }
      await send(.chatFinished(.success(())))
    } catch {
      await send(.chatFinished(.failure(error as? APIError ?? .unknown)))
    }
  }
  .cancellable(id: CancelID.chat, cancelInFlight: true)

case let .chatEvent(.delta(text)):
  state.reply += text
  return .none
```

`AIClient.chat` returns `AsyncThrowingStream<ChatEvent, Error>` built as in `swift-client.md`. Cancelling the effect terminates the stream's `Task`, which cancels the HTTPS request.

## `TestStore` example

```swift
import ComposableArchitecture
import Testing

@MainActor
struct NoteEditorTests {
  @Test
  func saveSuccess() async {
    let response = CreateNoteResponse(id: "n1", title: "Hi", visibility: .private, createdAt: Date(timeIntervalSince1970: 0), tags: [])
    let store = TestStore(initialState: NoteEditor.State(draft: CreateNoteRequest(title: "Hi"))) {
      NoteEditor()
    } withDependencies: {
      $0.notesClient.createNote = { request in
        #expect(request.title == "Hi")
        return response
      }
    }

    await store.send(.saveButtonTapped) { $0.isSaving = true }
    await store.receive(\.createNoteResponse.success) { $0.isSaving = false }
    await store.receive(\.delegate.saved)
  }

  @Test
  func saveUnauthenticatedBubblesUp() async {
    let store = TestStore(initialState: NoteEditor.State(draft: CreateNoteRequest(title: "Hi"))) {
      NoteEditor()
    } withDependencies: {
      $0.notesClient.createNote = { _ in
        throw APIError(kind: .unauthenticated, details: nil, debugMessage: "Sign in required")
      }
    }

    await store.send(.saveButtonTapped) { $0.isSaving = true }
    await store.receive(\.createNoteResponse.failure) { $0.isSaving = false }
    await store.receive(\.delegate.signInRequired)
  }

  @Test
  func retryableErrorShowsRetry() async {
    let store = TestStore(initialState: NoteEditor.State(draft: CreateNoteRequest(title: "Hi"))) {
      NoteEditor()
    } withDependencies: {
      $0.notesClient.createNote = { _ in throw APIError(kind: .transient, details: nil, debugMessage: "unavailable") }
    }

    await store.send(.saveButtonTapped) { $0.isSaving = true }
    await store.receive(\.createNoteResponse.failure) {
      $0.isSaving = false
      $0.alert = AlertState {
        TextState(APIError.Kind.transient.userMessage)
      } actions: {
        ButtonState(role: .cancel) { TextState("OK") }
        ButtonState(action: .retryButtonTapped) { TextState("Retry") }
      }
    }
  }
}
```

- Override only the closure the test exercises; the rest stay unimplemented and fail loudly if hit.
- Throw `APIError` directly from overrides — the live mapping is not in the path, so the test controls the exact kind.
- Never hit the emulator from `TestStore` tests. Emulator-backed tests are integration tests in a separate target that exercise `liveValue` against `firebase emulators:exec`.

## Integration test against the emulator (separate target)

```swift
@Test func createNoteAgainstEmulator() async throws {
  // Requires: firebase emulators:start --only functions,firestore,auth
  // and USE_FIREBASE_EMULATOR=1 in the test scheme, with Auth signed in anonymously in setUp.
  let client = NotesClient.liveValue
  let response = try await client.createNote(CreateNoteRequest(title: "Emulator"))
  #expect(!response.id.isEmpty)
}
```

Run rarely (CI nightly or pre-release), not on every unit-test run.

## Does not exist / common mistakes

- `@Dependency(\.functions) var functions: Functions` — injecting the raw Firebase object; reducers then depend on Firebase and tests need a live app. Inject a domain client.
- `Result<Response, any Error>` in the response action — loses `Equatable`, forces `XCTAssert` on `localizedDescription`.
- Forgetting `.cancellable(id:)` on a callable effect — double taps create two notes; leaving the screen leaks a request.
- Calling `notesClient` from the view's `.task {}` — bypasses the reducer; the effect is invisible to `TestStore`.
- Hand-writing `testValue` with real behaviour — hides unexpected calls.
- Importing `FirebaseFunctions` in the interface file — every module that uses the client now links Firebase.
- Performing the retry loop inside the reducer with `Task.sleep` — use the `withRetry` helper with `@Dependency(\.continuousClock)` (`error-mapping.md`).

# Streaming to iOS

Streaming exists so the user sees text appear while the model is still generating. The contract has three parts: the server sends typed chunks and then a final result; the Swift dependency exposes an `AsyncThrowingStream`; the TCA reducer accumulates chunks and treats the final result as the truth.

Requirements: `firebase-functions` ≥ 6.2 (streaming callables), Firebase iOS SDK ≥ 11.8 (`Callable.stream`). Both are within the bundle targets.

## Server: `onCall` with `sendChunk`

```ts
// functions/src/ai/askNote.ts
import { onCall, HttpsError, type CallableRequest, type CallableResponse } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";
import { GoogleGenAI, FinishReason } from "@google/genai";
import { z } from "zod";

const GEMINI_API_KEY = defineSecret("GEMINI_API_KEY");

const Input = z.object({ noteId: z.string().min(1), question: z.string().min(1).max(2000) });
export interface AskChunk { text: string }                       // streamed
export interface AskResult { answer: string; truncated: boolean } // final

export const askNote = onCall(
  { region: "asia-southeast1", enforceAppCheck: true, secrets: [GEMINI_API_KEY], timeoutSeconds: 120, memory: "256MiB", maxInstances: 20 },
  async (request: CallableRequest<unknown>, response: CallableResponse<AskChunk>): Promise<AskResult> => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in required");
    const parsed = Input.safeParse(request.data);
    if (!parsed.success) throw new HttpsError("invalid-argument", "Invalid input", parsed.error.flatten());
    const { noteId, question } = parsed.data;

    await consumeQuota(uid);                                       // cost-and-limits.md
    const noteText = await loadNoteText(uid, noteId, 30_000);      // not-found → HttpsError inside

    const ai = new GoogleGenAI({ apiKey: GEMINI_API_KEY.value() });
    const args = {
      model: "gemini-2.5-flash",
      contents: [{ role: "user" as const, parts: [{ text: `<note>\n${noteText}\n</note>\n\nQuestion: ${question}` }] }],
      config: { systemInstruction: ASK_SYSTEM, temperature: 0.3, maxOutputTokens: 1024, abortSignal: AbortSignal.timeout(100_000) },
    };

    let answer = "";
    let truncated = false;

    if (request.acceptsStreaming) {
      const stream = await ai.models.generateContentStream(args);
      for await (const chunk of stream) {
        const piece = chunk.text;
        if (piece) { answer += piece; response.sendChunk({ text: piece }); }
        if (chunk.candidates?.[0]?.finishReason === FinishReason.MAX_TOKENS) truncated = true;
        if (chunk.usageMetadata?.totalTokenCount) logger.info("gemini", { feature: "askNote", uid, ...chunk.usageMetadata });
      }
    } else {
      // Fallback for clients that call without streaming (older app versions, tests).
      const res = await ai.models.generateContent(args);
      answer = res.text ?? "";
      truncated = res.candidates?.[0]?.finishReason === FinishReason.MAX_TOKENS;
      logger.info("gemini", { feature: "askNote", uid, ...res.usageMetadata });
    }

    return { answer: filterOutput(answer), truncated };            // final result is always returned
  }
);
```

Rules:

- The handler always returns the full result, streaming or not. The client can miss chunks (backgrounded, reconnect) but never misses the return value.
- `sendChunk` payloads are JSON-serialisable objects; keep them tiny (`{ text }`). Do not send the accumulated string every time.
- Branch on `request.acceptsStreaming`; when false, `sendChunk` is a no-op but the streaming call would waste nothing — the branch exists so the non-streaming path is the plain, cheaper call.
- Errors thrown after chunks were sent still reach the client as an error on the stream. Do not try to "send an error chunk".
- Apply output filtering (`prompting-and-safety.md`) to the final `answer`; chunks are best-effort preview and may contain text the final filter removes — the client replaces the preview with the final value.
- Streaming with `responseSchema` yields fragments of one JSON document. Stream them only for a "typing" effect; parse and validate the concatenation once at the end and return the parsed object.

## Swift: the dependency

```swift
import ComposableArchitecture
import FirebaseFunctions

struct AskNoteRequest: Codable, Equatable { let noteId: String; let question: String }
struct AskChunk: Codable, Equatable { let text: String }
struct AskResult: Codable, Equatable { let answer: String; let truncated: Bool }

enum AskEvent: Equatable { case chunk(String); case result(AskResult) }

@DependencyClient
struct AIClient: Sendable {
  var askNote: @Sendable (_ request: AskNoteRequest) -> AsyncThrowingStream<AskEvent, any Error> = { _ in .finished() }
  var askNoteOnce: @Sendable (_ request: AskNoteRequest) async throws -> AskResult
}

extension AIClient: DependencyKey {
  static let liveValue: AIClient = {
    let functions = Functions.functions(region: "asia-southeast1")
    var streaming: Callable<AskNoteRequest, StreamResponse<AskChunk, AskResult>> = functions.httpsCallable("askNote")
    streaming.timeoutInterval = 130          // must exceed the server's timeoutSeconds (default is 70 s)
    let plain: Callable<AskNoteRequest, AskResult> = functions.httpsCallable("askNote")
    return AIClient(
      askNote: { request in
        AsyncThrowingStream { continuation in
          let task = Task {
            do {
              for try await item in streaming.stream(request) {
                switch item {
                case .message(let chunk): continuation.yield(.chunk(chunk.text))
                case .result(let final): continuation.yield(.result(final))
                }
              }
              continuation.finish()
            } catch {
              continuation.finish(throwing: error)
            }
          }
          continuation.onTermination = { _ in task.cancel() }   // cancelling the effect cancels the HTTP stream
        }
      },
      askNoteOnce: { try await plain($0) }
    )
  }()
}
```

`StreamResponse<Message, Result>` is the Firebase type: `.message` for every `sendChunk`, `.result` once for the return value. Declare the same function twice with different `Callable` types when you need both paths; the callable name is the same.

Error mapping is the usual `FunctionsErrorDomain` / `FunctionsErrorCode` (see `firebase-ios-contract` skill if present in the bundle, otherwise the fact sheet in `tca-pro`'s dependency guidance): `.resourceExhausted` → quota UI, `.deadlineExceeded`/`.unavailable` → retry affordance, `.failedPrecondition` → "blocked" message.

## TCA: the effect

```swift
@Reducer
struct AskNoteFeature {
  @ObservableState
  struct State: Equatable {
    let noteId: String
    var question = ""
    var preview = ""                 // accumulated chunks
    var answer: AskResult?           // final, authoritative
    var isStreaming = false
    var errorMessage: String?
  }
  enum Action: BindableAction {
    case binding(BindingAction<State>)
    case askButtonTapped
    case cancelButtonTapped
    case streamEvent(AskEvent)
    case streamFinished(Result<Void, any Error>)
  }
  @Dependency(\.aiClient) var aiClient
  private enum CancelID { case stream }

  var body: some Reducer<State, Action> {
    BindingReducer()
    Reduce { state, action in
      switch action {
      case .binding:
        return .none

      case .askButtonTapped:
        guard !state.question.isEmpty, !state.isStreaming else { return .none }
        state.preview = ""; state.answer = nil; state.errorMessage = nil; state.isStreaming = true
        return .run { [request = AskNoteRequest(noteId: state.noteId, question: state.question)] send in
          do {
            for try await event in aiClient.askNote(request) { await send(.streamEvent(event)) }
            await send(.streamFinished(.success(())))
          } catch {
            await send(.streamFinished(.failure(error)))
          }
        }
        .cancellable(id: CancelID.stream, cancelInFlight: true)

      case .cancelButtonTapped:
        state.isStreaming = false
        return .cancel(id: CancelID.stream)

      case let .streamEvent(.chunk(text)):
        state.preview += text
        return .none

      case let .streamEvent(.result(result)):
        state.answer = result           // replaces preview: the final value went through output filtering
        state.preview = result.answer
        return .none

      case .streamFinished(.success):
        state.isStreaming = false
        return .none

      case let .streamFinished(.failure(error)):
        state.isStreaming = false
        state.errorMessage = (error as NSError).domain == FunctionsErrorDomain ? userMessage(for: error) : "Something went wrong"
        return .none
      }
    }
  }
}
```

The view renders `store.preview` while `isStreaming`, then `store.answer?.answer`. Chunk actions arrive at token rate — that is fine for a text view; if a feature does heavy work per chunk, batch them in the dependency (see `tca-pro` → `references/performance.md`).

Testing: the `testValue` of `AIClient` yields a fixed sequence (`.chunk("Hel")`, `.chunk("lo")`, `.result(...)`) from an `AsyncThrowingStream` you build in the test; `TestStore` receives each `streamEvent` in order, then `streamFinished`. No network, no clock.

## Fallback and timeouts

- **Non-streaming fallback**: if `stream()` fails with a transport error before the first chunk (proxy, old SDK), call `askNoteOnce`. Do it in the dependency, not the reducer, so the reducer sees one stream either way.
- **Server timeout**: `timeoutSeconds` must exceed the worst-case generation time plus Firestore reads. 120 s for chat-style answers with `maxOutputTokens: 1024`; the `abortSignal` on the model call must be shorter than `timeoutSeconds` so the client gets `deadline-exceeded` rather than a dropped connection.
- **Client timeout**: `Callable` has a `timeoutInterval` property (default 70 s). Set it above the server `timeoutSeconds` for streaming callables, otherwise the client aborts a healthy stream (`var streaming = …; streaming.timeoutInterval = 130` as in the dependency above).
- **Backgrounding**: iOS suspends the app and the stream dies with a URL error. Treat it like a cancel; on foreground the user re-asks, or the feature re-runs the request through `askNoteOnce`. Do not attempt resume — the server has no session.
- **Idle streams**: Gemini can pause for seconds while thinking. Do not add a client-side "no chunk in 5 s" timeout; rely on the overall timeout.

## Does not exist / common mistakes

- `response.sendChunk` when `request.acceptsStreaming` is false — harmless no-op, but the plain call path is cheaper; branch.
- Forgetting to `return` the final value from a streaming handler — the client's `.result` never arrives and `stream()` ends without a result.
- `functions.httpsCallable("askNote").stream(...)` on an untyped callable — `stream` is on `Callable<Request, Response>`; declare the generic types.
- Declaring `Callable<AskNoteRequest, AskChunk>` and expecting `.result` — without `StreamResponse` the final value is decoded as another message or fails; use `StreamResponse<Chunk, Result>`.
- Sending the accumulated answer in every chunk — quadratic bytes on long answers.
- Running the `for try await` loop in the view or a `Task {}` in the reducer — it is an effect; keep it in `.run` with a cancel id.
- `Task.sleep`-based polling for "is it done" — the stream completes; there is nothing to poll.
- Using streaming for OCR/extraction jobs longer than a minute — that is a task-queue + status-document job (`document-pipeline.md`).

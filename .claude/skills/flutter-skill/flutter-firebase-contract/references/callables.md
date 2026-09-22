# Callables

`cloud_functions` 6.5.0. Everything here lives inside a repository implementation; no widget imports `cloud_functions`. The server half — `onCall`, zod validation, `HttpsError` — belongs to `firebase-skill` → `firebase-functions-pro`.

## Getting an instance

```dart
import 'package:cloud_functions/cloud_functions.dart';

final functions = FirebaseFunctions.instanceFor(region: 'asia-southeast1');
```

| Member | Signature | Note |
|---|---|---|
| `FirebaseFunctions.instance` | `FirebaseFunctions` | Default app, `us-central1` |
| `FirebaseFunctions.instanceFor` | `({FirebaseApp? app, String? region})` | Both named and optional |
| `httpsCallable` | `(String name, {HttpsCallableOptions? options})` | Deployed export name |
| `httpsCallableFromUrl` | `(String url, {HttpsCallableOptions? options})` | Hosting rewrite / custom domain |
| `httpsCallableFromUri` | `(Uri uri, {HttpsCallableOptions? options})` | Same, typed |
| `useFunctionsEmulator` | `(String host, int port, {bool automaticHostMapping = true})` | See `emulators-and-testing.md` |

- The region string must match the server's `setGlobalOptions({ region })`. A mismatch is `not-found` on every call, which reads like "the function does not exist" because from that region it does not.
- Hold one `FirebaseFunctions` and one `HttpsCallable` per operation in the repository. Creating a callable per call is cheap but pointless, and it hides the fact that the function name is part of the contract.

## `HttpsCallableOptions`

```dart
const HttpsCallableOptions({
  Duration timeout = const Duration(seconds: 60),
  bool limitedUseAppCheckToken = false,
  AbortSignal? webAbortSignal,
});
```

That is the whole surface. There is no `region`, no `appCheck`, no `retry`, no `headers`.

| Field | Use |
|---|---|
| `timeout` | Client-side deadline. Lower it to 15–20 s for CRUD so a dead network fails fast; raise it above the server's `timeoutSeconds` for slow calls, never below. |
| `limitedUseAppCheckToken` | `true` only when the server sets `consumeAppCheckToken: true`. Costs an extra round trip to the App Check backend per call. |
| `webAbortSignal` | Web only. Ignored on the method-channel platforms. |

A client `timeout` shorter than the server's `timeoutSeconds` means the client gives up first and reports `deadline-exceeded` while the server keeps running and commits its writes. Decide deliberately which side wins.

## Calling

```dart
final result = await callable.call<Map<String, dynamic>>(request.toJson());
final response = CreateNoteResponse.fromJson(result.data);
```

`HttpsCallable.call<T>([dynamic parameters]) → Future<HttpsCallableResult<T>>`.

**`T` is not checked.** The implementation is `HttpsCallableResult<T>._(await delegate.call(parameters))` — a raw assignment. `call<CreateNoteResponse>()` compiles and throws `TypeError` the first time it runs. The only safe `T` values are the ones the wire can actually produce: `Map<String, dynamic>`, `List<dynamic>`, `String`, `num`, `bool`, `void`.

```dart
// Before — throws TypeError at runtime
final res = await callable.call<CreateNoteResponse>(request.toJson());
return res.data;

// After
final res = await callable.call<Map<String, dynamic>>(request.toJson());
return CreateNoteResponse.fromJson(res.data);
```

Request parameters must be JSON-shaped: `null`, `String`, `num`, `bool`, `List`, or `Map` with `String` keys. The plugin asserts this in debug builds. A `DateTime`, an `Enum`, a Firestore `Timestamp`, or a model object passed directly fails the assertion in debug and produces a platform exception in release. Always pass `request.toJson()`.

## The nested-type traps

The method-channel delegate runs every response through a recursive converter that rebuilds maps as `Map<String, dynamic>` and lists as `List<dynamic>`. That fixes the historical `Map<Object?, Object?>` cast failure on nested objects — with a current plugin, `result.data['nested']['field']` works. Three traps remain:

| Trap | Why | Correct form |
|---|---|---|
| `json['tags'] as List<String>` | The converter produces `List<dynamic>` | `(json['tags'] as List).cast<String>()` |
| `json['score'] as double` | JSON `7` decodes to `int`, `7.0` to `double` | `(json['score'] as num).toDouble()` |
| `json['items'] as List<Map<String, dynamic>>` | Outer list is `List<dynamic>` | `[for (final e in json['items'] as List) Item.fromJson(e as Map<String, dynamic>)]` |

The `double` trap is the one that survives review: a server field that happens to hold `0` in every test fixture and `0.5` in production crashes only in production. Write `as num` and convert.

Web uses a different delegate. If the app ships web, re-verify these three with a real call rather than assuming parity.

## Typed wrappers

Put the name, the options, the encode, and the decode in one place per operation:

```dart
final class FunctionsApi {
  FunctionsApi(this._functions);

  final FirebaseFunctions _functions;

  Future<R> call<R>(
    String name, {
    required Map<String, Object?> request,
    required R Function(Map<String, dynamic> json) decode,
    Duration timeout = const Duration(seconds: 20),
    bool limitedUse = false,
  }) async {
    final callable = _functions.httpsCallable(
      name,
      options: HttpsCallableOptions(
        timeout: timeout,
        limitedUseAppCheckToken: limitedUse,
      ),
    );
    try {
      final result = await callable.call<Map<String, dynamic>>(request);
      return decode(result.data);
    } on FirebaseFunctionsException catch (e, s) {
      Error.throwWithStackTrace(ApiFailure.fromFunctions(e), s);
    } on TypeError catch (e, s) {
      Error.throwWithStackTrace(DecodingFailure(debugMessage: '$e'), s);
    }
  }
}
```

Keep the function names in one place so a rename is one edit and a grep finds every caller:

```dart
abstract final class Fn {
  static const createNote = 'createNote';
  static const listNotes = 'listNotes';
  static const redeemCode = 'redeemCode';
  static const chat = 'chat';
}
```

Void responses still return an object (`{}` on the server). Decode them as `(_) {}` rather than typing the call as `call<void>()`.

## Streaming

The Dart SDK does support streaming callables. `HttpsCallable.stream<T, R>([Object? input]) → Stream<StreamResponse<T, R>>`, against a server callable that writes with `response.sendChunk(...)` and then returns a final value.

```dart
sealed class StreamResponse<T, R> {}          // sealed — switch is exhaustive
final class Chunk<T, R> extends StreamResponse<T, R> { final T partialData; }
final class Result<T, R> extends StreamResponse<T, R> { final HttpsCallableResult<R> result; }
```

```dart
Stream<ChatEvent> streamChat(String prompt) async* {
  final callable = _functions.httpsCallable(
    Fn.chat,
    options: const HttpsCallableOptions(timeout: Duration(minutes: 3)),
  );
  final stream = callable.stream<Map<String, dynamic>, Map<String, dynamic>>({
    'prompt': prompt,
  });

  try {
    await for (final event in stream) {
      switch (event) {
        case Chunk(:final partialData):
          yield ChatEvent.delta(partialData['text'] as String);
        case Result(:final result):
          yield ChatEvent.completed(result.data['text'] as String);
      }
    }
  } on FirebaseFunctionsException catch (e, s) {
    Error.throwWithStackTrace(ApiFailure.fromFunctions(e), s);
  }
}
```

- The generics are `<T, R>`: `T` is the shape of each `sendChunk` payload, `R` the shape of the final return value. Both are unchecked casts, exactly like `call<T>()` — use `Map<String, dynamic>` for both and decode yourself.
- `Result` arrives once, last. If the server throws after sending chunks, the stream emits an error and `Result` never arrives: keep what was streamed and surface the failure alongside it.
- Cancelling the `StreamSubscription` (or letting a Riverpod `StreamProvider` dispose) tears down the underlying event channel.
- Each `stream()` call gets its own event-channel id, so concurrent calls to the same function do not collide.
- A streaming server callable still `return`s its final value, so the same function can be invoked with plain `call()` when the client does not want chunks.
- Streaming is a foreground transport. Work that must survive the app being backgrounded belongs in a task queue plus a status document — see `firestore-streams.md`.

## Cancellation and lifecycle

- There is no `cancel()` on `HttpsCallable`. A `call()` that is no longer wanted keeps running; guard the result with a liveness check (`if (!ref.mounted) return;`) instead of pretending it was cancelled.
- `Future.timeout` on top of `call()` does not cancel the request either — it only stops you waiting. Prefer `HttpsCallableOptions.timeout`, which the native SDK honours.
- A `stream()` subscription **is** cancellable, and cancelling it stops the request.

## Does not exist / common mistakes

- `FirebaseFunctions.instance` while the server is deployed to `asia-southeast1` — every call fails `not-found`.
- `call<MyModel>()` — the generic is an unchecked cast; it throws `TypeError`.
- `HttpsCallableOptions(region: ...)` — no such field; region is on the instance.
- `HttpsCallableOptions(requireLimitedUseAppCheckTokens: true)` — that is the Swift spelling. In Dart it is `limitedUseAppCheckToken` (singular, no `require`).
- `callable.call(myModel)` — the parameters must already be JSON; pass `myModel.toJson()`.
- `callable.call(DateTime.now())` or a map containing a `DateTime`/`Timestamp` — fails the debug assertion, fails natively in release. Send `toIso8601String()`.
- `httpsCallable('notes.create')` — a dotted name is not a deployable export. See `firebase-skill` → `firebase-ios-contract` → `references/envelope-and-naming.md` for the naming rules both sides share.
- `functions.useFunctionsEmulator(...)` after the first call — configure the instance once, at startup.
- Wrapping every call in `Future.timeout` and calling it a timeout policy — set `HttpsCallableOptions.timeout`.
- Polling a callable on a `Timer` to watch progress — use a Firestore listener.

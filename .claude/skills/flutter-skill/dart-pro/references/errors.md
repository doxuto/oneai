# Errors and exceptions

Dart lets you throw anything, which means the discipline has to come from you. The decisions are: throw or return, which type to throw, how narrow the `catch` is, whether the stack trace survives, and where the failure ends up when nobody catches it. This file covers all five, including the handoff to Flutter's own error reporting.

## `Exception` vs `Error`

| | `Exception` | `Error` |
|---|---|---|
| Means | a condition the caller could reasonably anticipate | a programming mistake |
| Examples | `FormatException`, `TimeoutException`, `HttpException`, your domain exceptions | `StateError`, `ArgumentError`, `RangeError`, `TypeError`, `UnimplementedError`, `LateInitializationError` |
| Should be caught | yes, at a boundary | no — fix the code |
| `stackTrace` member | no | yes (`Error.stackTrace`, null before throwing) |

Rules:

- Throw an `Exception` subtype for recoverable, expected failures. Throw an `Error` subtype (`ArgumentError.value`, `StateError`) for contract violations by the caller.
- Never `throw 'something went wrong'`. Strings carry no type, no `toString` contract, and cannot be caught with `on`. `only_throw_errors` flags it.
- `assert(cond, 'message')` for invariants — stripped in release, so never for input validation.
- Define domain exceptions as small final classes implementing `Exception`:

```dart
final class NoteNotFoundException implements Exception {
  const NoteNotFoundException(this.id);
  final String id;
  @override
  String toString() => 'NoteNotFoundException($id)';
}
```

## Throwing vs returning a `Result`

| Prefer throwing when | Prefer a sealed result when |
|---|---|
| The failure is exceptional and most callers cannot act on it | Every caller must branch, e.g. a sign-in form |
| The call is deep in a call stack with nothing useful to do in between | The failure modes are a closed, named set |
| There are many failure modes and one handler at the top | The type is crossing a UI boundary |
| Interop forces it (`jsonDecode`, platform channels) | You want the analyzer to enforce handling |

A `Result` type that nobody switches over exhaustively is worse than an exception: it adds ceremony and loses the stack trace.

```dart
sealed class SignInResult {
  const SignInResult();
}

final class SignInOk extends SignInResult {
  const SignInOk(this.uid);
  final String uid;
}

final class SignInRejected extends SignInResult {
  const SignInRejected(this.reason);
  final SignInReason reason; // enum: wrongPassword, tooManyAttempts, …
}

/// Keep this arm. A result type with no "unanticipated" case forces
/// callers to swallow real bugs — and always carry the StackTrace.
final class SignInFailed extends SignInResult {
  const SignInFailed(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}
```

Converting at the boundary is the usual shape:

```dart
Future<SignInResult> signIn(String email, String password) async {
  try {
    final uid = await _auth.signIn(email, password);
    return SignInOk(uid);
  } on AuthRejectedException catch (e) {
    return SignInRejected(e.reason);
  } catch (e, st) {
    return SignInFailed(e, st);
  }
}
```

## `try` / `on` / `catch` / `finally`

```dart
try {
  await parse(body);
} on FormatException catch (e) {
  report(e);                  // type known, no stack trace needed
} on TimeoutException catch (e, st) {
  report(e, st);
} catch (e, st) {
  report(e, st);
  rethrow;                    // do not absorb what you do not understand
} finally {
  await sink.close();         // runs on every path, including rethrow
}
```

| Form | When |
|---|---|
| `on T catch (e)` | you know the type and do not need the trace |
| `on T catch (e, st)` | you will log or forward |
| `catch (e)` | almost never — enable `avoid_catches_without_on_clauses` |
| `catch (e, st) { ...; rethrow; }` | acceptable: observe and re-raise |
| `on T` (no `catch`) | you only care that it happened |

`finally` runs even when the `try` block returns or the exception is rethrown. It cannot swallow the exception unless it itself returns or throws — `throw_in_finally` flags the latter.

`whenComplete` is the `Future` equivalent of `finally`, not of `catch`: it runs on both paths and, if it returns a future, delays completion until that future finishes. It does **not** handle the error. Inside an `async` function prefer real `try`/`finally`.

```dart
fetch().whenComplete(spinner.hide);           // Before: reads like error handling, is not
try { await fetch(); } finally { spinner.hide(); }  // After
```

## Never swallow

```dart
try { await sync(); } catch (_) {}    // Before — the worst line in any Dart codebase

try {                                  // After — narrow, record the trace, decide
  await sync();
} on SocketException catch (e, st) {
  log('sync.offline', error: e, stackTrace: st);
  _scheduleRetry();
}
```

An empty or log-only `catch (e)` around a whole method also catches `TypeError`, `LateInitializationError`, `StackOverflowError`, and every future bug in that block. If you must catch broadly (an isolate entry point, a background task runner), `rethrow` or forward to the same reporter the framework uses.

## Stack traces

- `rethrow` preserves the original stack trace. `throw e;` inside a `catch` **replaces** it with the current one — the single most common way stack traces are destroyed in Dart.
- `catch (e, st)` is the only way to capture a trace for a non-`Error` throwable.
- `Error.throwWithStackTrace(error, stackTrace)` re-raises with a supplied trace — use it when wrapping an error in a domain type without losing the origin.
- Across an `await`, the stack trace of an error thrown before the await does not include the caller's frames by default. `package:stack_trace` (`Chain.capture`) reassembles them; in Flutter, the framework already does some of this for errors it reports.

```dart
} catch (e) { throw RepositoryException(e.toString()); }              // Before — trace lost
} catch (e, st) { Error.throwWithStackTrace(RepositoryException(e), st); } // After
```

## Errors across async gaps

- An error thrown in an `async` function before any `await` still surfaces as a failed future, not a synchronous throw.
- An error in a `Future` nobody awaits goes to `Zone.current.handleUncaughtError` — in a Flutter app, to `PlatformDispatcher.instance.onError` (or the surrounding `runZonedGuarded`).
- `try`/`catch` around a `StreamSubscription` callback catches nothing. Stream errors arrive through `onError`:

```dart
try { stream.listen(_handle); } catch (e) { /* never runs */ }          // Before
stream.listen(_handle, onError: (Object e, StackTrace st) => report(e, st)); // After
```

- `await for` **does** route stream errors to a surrounding `try`/`catch`.
- `Future.wait` reports one error and drops the rest; see `async.md`.

## Handing off to the framework

Two sinks, both set before `runApp`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Errors caught by the Flutter framework (build, layout, paint, gestures).
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);          // keep the red screen / console dump
    Crash.report(details.exception, details.stack);
  };

  // 2. Uncaught errors from the root isolate that the framework did not catch.
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    Crash.report(error, stack);
    return true; // handled — returning false falls back to printing to stderr
  };

  runApp(const App());
}
```

- `FlutterError.onError` is a `void Function(FlutterErrorDetails)`. Replacing it without calling `FlutterError.presentError(details)` silences the console and the error widget.
- `PlatformDispatcher.instance.onError` returns `bool`: `true` means handled. It covers the **root isolate only**; background isolates must forward errors to it themselves (`Isolate.addErrorListener`, or catch at the entry point).
- With these two in place you do not also need `runZonedGuarded` for most apps; use it only when you need a zone for other reasons (zone values, captured `print`). Do not set the zone handler and then set `PlatformDispatcher.onError` inside a *different* zone — the handoff silently stops working.
- Errors inside `FlutterError.onError` itself are not reported anywhere. Keep that closure trivial.

## Logging

```dart
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

developer.log('note.sync.failed', name: 'notes', error: e, stackTrace: st, level: 1000);
if (kDebugMode) debugPrint('cache size: ${cache.length}');
```

`print` is banned (`avoid_print`): it is unthrottled, ships to release builds, and is truncated by the Android log buffer. `debugPrint` throttles and is a no-op-able hook; `developer.log` carries `error`, `stackTrace`, `name`, and `level` into DevTools.

Mapping platform and Firebase error codes to domain errors is `flutter-firebase-contract`; presenting an error state in the UI is `flutter-widgets-pro`.

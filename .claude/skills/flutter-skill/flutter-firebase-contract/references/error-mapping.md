# Error mapping

Three layers, each typed:

1. Server throws `HttpsError(code, message, details)`.
2. The plugin delivers a `FirebaseFunctionsException` whose `code` is the same code as a lowercase hyphenated string, `message` is the server's developer text, and `details` is the server's `details` value as `dynamic`.
3. The repository converts it to a sealed `ApiFailure`; notifiers and widgets switch on `ApiFailure`.

Nothing above the repository imports `cloud_functions`. No widget ever reads `e.message`.

## Code mapping table

Mirrors the table in `firebase-skill` → `firebase-ios-contract` → `references/error-mapping.md`. The server codes, the retry policy, and the UX decision are identical; only the middle column changes language.

| `HttpsError` code (TS) | `FirebaseFunctionsException.code` (Dart) | `ApiFailure` | Retry | UX |
|---|---|---|---|---|
| `invalid-argument` | `'invalid-argument'` | `InvalidArgumentFailure` | No | Client bug. Log with `details.issues`, show generic error. |
| `unauthenticated` | `'unauthenticated'` | `UnauthenticatedFailure` | After re-auth | Route to sign-in; keep the draft. Also App Check failure — see below. |
| `permission-denied` | `'permission-denied'` | `PermissionDeniedFailure` | No | Explain what is required using `details.reason` (`anonymous`, `role`, `plan`). |
| `not-found` | `'not-found'` | `NotFoundFailure` | No | Empty state / pop the route. |
| `already-exists` | `'already-exists'` | `AlreadyExistsFailure` | No | Usually treat as success (idempotent create) or show "already done". |
| `failed-precondition` | `'failed-precondition'` | `PreconditionFailure(reason)` | After fixing | `minVersion` → update gate; `emailUnverified` → verify flow; `subscriptionRequired` → paywall. |
| `resource-exhausted` | `'resource-exhausted'` | `QuotaExceededFailure(resetAt)` | After `resetAt` | Paywall or "try again at …". |
| `aborted` | `'aborted'` | `ConflictFailure` | Once, immediately | Silent retry once, then show conflict. |
| `out-of-range` | `'out-of-range'` | `InvalidArgumentFailure` | No | Same as invalid-argument. |
| `unimplemented` | `'unimplemented'` | `FeatureUnavailableFailure` | No | Hide the feature. |
| `deadline-exceeded` | `'deadline-exceeded'` | `TransientFailure` | Backoff | "Taking too long" + retry button. |
| `unavailable` | `'unavailable'` | `TransientFailure` | Backoff | Offline banner / retry. |
| `internal` | `'internal'` | `ServerFailure` | Once | Generic error; log for support. |
| `cancelled` | `'cancelled'` | `CancelledFailure` | — | Ignore (the user navigated away). |
| `unknown`, `data-loss` | `'unknown'`, `'data-loss'` | `ServerFailure` | Once | Generic error. |
| (transport error, no server code) | `'unavailable'` / `'deadline-exceeded'` | `TransientFailure` | Backoff | Offline banner / retry. |

Keep this table and the server one in `firebase-skill` → `firebase-functions-pro` → `references/errors-and-logging.md` in agreement.

### The Dart-specific row

The last row is where Dart differs from Swift. The iOS SDK reports an offline call as an `NSURLErrorDomain` error and the app maps it to a separate `network` case. The Flutter plugin does not: on Android the platform code turns a socket `IOException` into `unavailable`, and a cancelled or timed-out `IOException` into `deadline-exceeded`, explicitly "to match iOS & Web". So:

- There is no separate network domain to branch on. Offline is `'unavailable'`.
- `NetworkFailure` is worth keeping only for errors that never reach the plugin — for example a `SocketException` from your own connectivity pre-flight. Do not write `if (e is SocketException)` around a callable; it will not fire.
- When `details` carries no `code` at all, the plugin defaults to `'unknown'`. Treat unrecognised codes as `ServerFailure`, never as success.

## `details` payload

The server puts a small JSON object in `details`; keys are defined per code. Decode leniently — a server that forgets a key must not break the app.

```dart
final class ApiErrorDetails {
  const ApiErrorDetails({
    this.reason,
    this.minVersion,
    this.limit,
    this.resetAt,
    this.retryAfterSeconds,
    this.field,
    this.issues = const [],
  });

  factory ApiErrorDetails.fromJson(Map<String, dynamic> json) => ApiErrorDetails(
        reason: json['reason'] as String?,
        minVersion: json['minVersion'] as String?,
        limit: (json['limit'] as num?)?.toInt(),
        resetAt: switch (json['resetAt']) {
          final String s => DateTime.tryParse(s),
          _ => null,
        },
        retryAfterSeconds: (json['retryAfterSeconds'] as num?)?.toInt(),
        field: json['field'] as String?,
        issues: [
          for (final raw in (json['issues'] as List?) ?? const [])
            if (raw is Map)
              ApiIssue(
                path: '${raw['path'] ?? ''}',
                message: '${raw['message'] ?? ''}',
              ),
        ],
      );

  final String? reason;            // permission-denied / failed-precondition discriminator
  final String? minVersion;        // failed-precondition, reason == 'appOutdated'
  final int? limit;                // resource-exhausted
  final DateTime? resetAt;         // resource-exhausted, ISO-8601
  final int? retryAfterSeconds;    // unavailable / resource-exhausted
  final String? field;             // invalid-argument (single-field form)
  final List<ApiIssue> issues;     // invalid-argument (zod flatten)

  static ApiErrorDetails? tryFrom(Object? raw) =>
      raw is Map ? ApiErrorDetails.fromJson(Map<String, dynamic>.from(raw)) : null;
}

final class ApiIssue {
  const ApiIssue({required this.path, required this.message});
  final String path;
  final String message;
}
```

`FirebaseFunctionsException.details` is `dynamic` and arrives already normalised to `Map<String, dynamic>` / `List<dynamic>` by the plugin, but it can be `null`, a `String`, or a `List` if the server sent one. Guard with `raw is Map` rather than casting.

## `ApiFailure`

```dart
import 'package:cloud_functions/cloud_functions.dart';

sealed class ApiFailure implements Exception {
  const ApiFailure({this.details, this.debugMessage = ''});

  /// Decoded server `details`. Never shown to a user.
  final ApiErrorDetails? details;

  /// The server `message` — English developer text, for logs only.
  final String debugMessage;

  factory ApiFailure.fromFunctions(FirebaseFunctionsException e) {
    final details = ApiErrorDetails.tryFrom(e.details);
    final message = e.message ?? '';
    return switch (e.code) {
      'invalid-argument' || 'out-of-range' =>
        InvalidArgumentFailure(details: details, debugMessage: message),
      'unauthenticated' =>
        UnauthenticatedFailure(details: details, debugMessage: message),
      'permission-denied' =>
        PermissionDeniedFailure(details: details, debugMessage: message),
      'not-found' => NotFoundFailure(details: details, debugMessage: message),
      'already-exists' =>
        AlreadyExistsFailure(details: details, debugMessage: message),
      'failed-precondition' =>
        PreconditionFailure(details: details, debugMessage: message),
      'resource-exhausted' =>
        QuotaExceededFailure(details: details, debugMessage: message),
      'aborted' => ConflictFailure(details: details, debugMessage: message),
      'unimplemented' =>
        FeatureUnavailableFailure(details: details, debugMessage: message),
      'deadline-exceeded' || 'unavailable' =>
        TransientFailure(details: details, debugMessage: message),
      'cancelled' => CancelledFailure(details: details, debugMessage: message),
      _ => ServerFailure(details: details, debugMessage: message),
    };
  }

  bool get isRetryable => switch (this) {
        TransientFailure() || NetworkFailure() || ServerFailure() || ConflictFailure() => true,
        _ => false,
      };

  String? get reason => details?.reason;
}

// One line each — the base class holds the state, the subtype is the identity.
final class InvalidArgumentFailure extends ApiFailure { const InvalidArgumentFailure({super.details, super.debugMessage}); }
final class UnauthenticatedFailure extends ApiFailure { const UnauthenticatedFailure({super.details, super.debugMessage}); }
final class PermissionDeniedFailure extends ApiFailure { const PermissionDeniedFailure({super.details, super.debugMessage}); }
final class NotFoundFailure extends ApiFailure { const NotFoundFailure({super.details, super.debugMessage}); }
final class AlreadyExistsFailure extends ApiFailure { const AlreadyExistsFailure({super.details, super.debugMessage}); }
final class PreconditionFailure extends ApiFailure { const PreconditionFailure({super.details, super.debugMessage}); }
final class ConflictFailure extends ApiFailure { const ConflictFailure({super.details, super.debugMessage}); }
final class FeatureUnavailableFailure extends ApiFailure { const FeatureUnavailableFailure({super.details, super.debugMessage}); }
final class TransientFailure extends ApiFailure { const TransientFailure({super.details, super.debugMessage}); }
final class ServerFailure extends ApiFailure { const ServerFailure({super.details, super.debugMessage}); }
final class NetworkFailure extends ApiFailure { const NetworkFailure({super.details, super.debugMessage}); }
final class CancelledFailure extends ApiFailure { const CancelledFailure({super.details, super.debugMessage}); }
final class DecodingFailure extends ApiFailure { const DecodingFailure({super.details, super.debugMessage}); }
final class UnknownFailure extends ApiFailure { const UnknownFailure({super.details, super.debugMessage}); }

final class QuotaExceededFailure extends ApiFailure {
  const QuotaExceededFailure({super.details, super.debugMessage});
  DateTime? get resetAt => details?.resetAt;
}
```

A sealed class can only be extended from the same library, so `ApiFailure` and every subtype live in one file (`lib/core/api_failure.dart`). That is the constraint that makes exhaustiveness possible; splitting them across files turns the `switch` non-exhaustive and the analyzer will say so.

Because `ApiFailure` is sealed, `switch` over it is exhaustive: adding a case makes every incomplete `switch` a compile error. That is the point — a `default:` branch in a failure switch throws that away, so use one only in the presentation layer where a generic message is genuinely correct.

Convert at the boundary, once per repository:

```dart
try {
  final res = await callable.call<Map<String, dynamic>>(request.toJson());
  return Response.fromJson(res.data);
} on FirebaseFunctionsException catch (e, s) {
  Error.throwWithStackTrace(ApiFailure.fromFunctions(e), s);
} on TypeError catch (e, s) {
  Error.throwWithStackTrace(DecodingFailure(debugMessage: '$e'), s);
}
```

`Error.throwWithStackTrace` preserves the original stack trace, which `throw` would replace. `FirebaseFunctionsException` extends `FirebaseException`, so `on FirebaseException` also catches it — catch the specific type first if you handle both.

## Retry policy

Implement once, next to the repository, never ad hoc in a notifier:

```dart
typedef Sleep = Future<void> Function(Duration);

Future<T> withRetry<T>(
  Future<T> Function() operation, {
  int maxAttempts = 3,
  Sleep sleep = _defaultSleep,
  Random? random,
}) async {
  final rng = random ?? Random();
  var attempt = 0;
  while (true) {
    try {
      return await operation();
    } on ApiFailure catch (failure) {
      attempt++;
      if (!failure.isRetryable || attempt >= maxAttempts) rethrow;
      final after = failure.details?.retryAfterSeconds;
      final base = after != null
          ? Duration(seconds: after)
          : Duration(milliseconds: 250 * (1 << attempt));
      await sleep(base + Duration(milliseconds: rng.nextInt(300)));
    }
  }
}

Future<void> _defaultSleep(Duration d) => Future<void>.delayed(d);
```

Injecting `sleep` and `random` is what keeps the retry test instant and deterministic; a hard-coded `Future.delayed` makes every retry test sleep for real.

- `ConflictFailure` (`aborted`): retry once, immediately — the server transaction already retried and a second client attempt usually succeeds.
- `TransientFailure`: exponential backoff with jitter, cap 3 attempts, honour `retryAfterSeconds`.
- `ServerFailure` (`internal`): retry once. Twice is a bug, not weather.
- Never retry `InvalidArgumentFailure`, `PermissionDeniedFailure`, `NotFoundFailure`, `AlreadyExistsFailure`, `PreconditionFailure`, `QuotaExceededFailure` before `resetAt`, or `UnauthenticatedFailure` before re-auth.
- Non-idempotent callables must not auto-retry `TransientFailure` after the request may have reached the server. Either make them idempotent — the client generates the document id and the server uses `create()` — or do not retry them. When in doubt, generate the id on the client.
- Riverpod 3 retries failing providers automatically (up to 10 attempts, 200 ms doubling to 6.4 s). For a form submission that must fail fast, pass `retry: (count, error) => null` on the provider; see `riverpod-pro`.

## `unauthenticated` vs `permission-denied`

| | `unauthenticated` | `permission-denied` |
|---|---|---|
| Server meaning | Do not know who you are: no token, expired, revoked, or App Check failed | Know who you are; you may not do this |
| Typical cause | Signed out, token refresh failed, App Check debug token missing, replayed limited-use token | Anonymous where a permanent account is required, missing custom claim, not the owner, plan too low |
| UX | Present sign-in or re-auth, preserve the in-progress state, retry after success | Explain and offer the fix: link account, upgrade, request access. No retry button. |
| App reaction | Bubble to the router and redirect | Inline message or dialog driven by `details.reason` |

App Check failures on a callable with `enforceAppCheck: true` also arrive as `unauthenticated`. In debug, if every call fails `unauthenticated` while the user is clearly signed in, check the App Check debug token before anything else — see `auth-and-appcheck.md`.

## Presenting failures

```dart
String messageFor(ApiFailure failure, AppLocalizations l10n) => switch (failure) {
      TransientFailure() || NetworkFailure() => l10n.errorConnection,
      QuotaExceededFailure(:final resetAt) when resetAt != null =>
        l10n.errorQuotaUntil(resetAt),
      QuotaExceededFailure() => l10n.errorQuota,
      PreconditionFailure(reason: 'appOutdated') => l10n.errorUpdateRequired,
      PreconditionFailure() => l10n.errorPrecondition,
      PermissionDeniedFailure() => l10n.errorNoAccess,
      NotFoundFailure() => l10n.errorGone,
      UnauthenticatedFailure() => l10n.errorSignInRequired,
      _ => l10n.errorGeneric,
    };
```

Copy is keyed on the failure type plus `details.reason` and localised in the app. Log `debugMessage` and `details` where the failure is caught, not from the widget.

## Testing the mapping

No network and no Firebase needed — construct the exception directly:

```dart
test('failed-precondition with minVersion maps to PreconditionFailure', () {
  final failure = ApiFailure.fromFunctions(
    FirebaseFunctionsException(
      code: 'failed-precondition',
      message: 'App update required',
      details: {'reason': 'appOutdated', 'minVersion': '2.3.0'},
    ),
  );

  expect(failure, isA<PreconditionFailure>());
  expect(failure.reason, 'appOutdated');
  expect(failure.details?.minVersion, '2.3.0');
  expect(failure.isRetryable, isFalse);
});
```

`FirebaseFunctionsException`'s constructor is public: `FirebaseFunctionsException({required String message, required String code, StackTrace? stackTrace, dynamic details})`.

## Does not exist / common mistakes

- `catch (e) { if (e.code == 'PERMISSION_DENIED') }` — the codes are lowercase and hyphenated, and Android explicitly lowercases the native enum name before sending it.
- `on FirebaseFunctionsException` in a widget — the conversion belongs in the repository; widgets switch on `ApiFailure`.
- `e.details['reason']` without a type check — `details` is `dynamic` and may be `null` or a `String`.
- `e.details as Map<String, String>` — values are mixed types (`int`, `List`); use `Map<String, dynamic>.from`.
- Showing `e.message` in a `SnackBar` — untranslated developer text, sometimes with internals.
- Branching on `SocketException` around a callable — the plugin has already converted it to `'unavailable'`.
- Mapping `permission-denied` to the sign-in screen — the user is signed in; they need a different fix.
- Treating everything as retryable — retries `invalid-argument` forever and double-creates on `internal`.
- `throw ApiFailure.fromFunctions(e)` without `Error.throwWithStackTrace` — loses the originating stack trace.
- A `default:` arm in a failure `switch` inside the data layer — defeats the exhaustiveness the sealed class exists for.

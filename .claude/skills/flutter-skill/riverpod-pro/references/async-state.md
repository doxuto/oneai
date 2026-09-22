# `AsyncValue`, errors, and retry

`AsyncValue<T>` is the return type of every async provider and the `state` type of every
`AsyncNotifier`. In Riverpod 3 it is a **sealed** class with exactly three subclasses —
`AsyncData<T>`, `AsyncLoading<T>`, `AsyncError<T>` — which makes `switch` exhaustive and makes
`when` unnecessary in most places. Load this file when reviewing async UI, error handling, or
anything that touches `valueOrNull`, retry, or `ProviderException`.

## Constructors and accessors

```dart
const AsyncValue.data(T value);
const AsyncValue.loading({num progress});
const AsyncValue.error(Object error, StackTrace stackTrace);
```

| Accessor | Type | Meaning |
|---|---|---|
| `value` | `T?` | The value if one is known, else `null`. **Renamed from `valueOrNull` in 3.0.** In an error or loading state it returns the previous value when there is one, and `null` when there is not. |
| `requireValue` | `T` | The value, or rethrows the error, or throws `AsyncValueIsLoadingException`. |
| `error` / `stackTrace` | `Object?` / `StackTrace?` | Set only on `AsyncError`. |
| `hasValue` / `hasError` | `bool` | |
| `isLoading` | `bool` | A new value is being computed — true during refresh even when data is present. |
| `isRefreshing` | `bool` | Recomputing after an explicit `refresh`, with a previous value or error retained. |
| `isReloading` | `bool` | Recomputing because a dependency changed. |
| `isFromCache` | `bool` | The value came from offline persistence rather than the source. |
| `progress` | `num?` | Progress reported by `AsyncLoading(progress: ...)`. |
| `retrying` | `bool` | An emitted error is currently being retried by the automatic retry. |
| `asData` / `asError` | `AsyncData<T>?` / `AsyncError<T>?` | Upcasts, or `null`. |

`AsyncValue.value` is nullable. During an error or a refresh it yields the previous value when
one exists and `null` when it does not, so `.value!` on an error path crashes for a provider that
never produced data — pattern-match instead.

## Prefer `switch` over `when`

```dart
// Preferred: exhaustive, and the compiler enforces every case.
return switch (ref.watch(userProvider)) {
  AsyncData(:final value) => UserView(user: value),
  AsyncError(:final error, :final stackTrace) => ErrorView(error, stackTrace),
  AsyncLoading() => const CircularProgressIndicator(),
};
```

The "keep the last good data visible" variant orders the cases by what is known rather than by
subclass:

```dart
return switch (ref.watch(userProvider)) {
  AsyncValue(:final value?) => UserView(user: value),         // data, or stale data mid-refresh
  AsyncValue(:final error?) => ErrorView(error),
  _ => const CircularProgressIndicator(),
};
```

Caveat: `:final value?` null-checks the value, so it misbehaves when `T` itself is nullable —
`AsyncData<String?>(null)` falls through to the loading branch. `riverpod_lint`'s
`async_value_nullable_pattern` rule flags exactly this. For nullable `T`, match on the subclass:

```dart
return switch (state) {
  AsyncData(:final value) => Text(value ?? 'none'),
  AsyncError(:final error) => Text('$error'),
  _ => const CircularProgressIndicator(),
};
```

`when(data:, error:, loading:)` and `maybeWhen(..., orElse:)` still exist and are fine for a
one-line mapping, but they give no exhaustiveness checking and their positional callback order is
easy to get wrong. `map`/`maybeMap`/`mapOrNull` take the subclass rather than the unwrapped value;
`whenData` and `whenOrNull` handle partial cases.

## Preserving data across a refresh

`AsyncValue` keeps the previous value while recomputing, which is what makes pull-to-refresh
pleasant: `isLoading` is true, `hasValue` is still true, and `value` still holds the old data.
Three flags distinguish the causes:

| Flag | Cause |
|---|---|
| `isLoading` only, `hasValue` false | genuine first load |
| `isRefreshing` | `ref.refresh`/`ref.invalidate` on this provider |
| `isReloading` | a watched dependency changed |

A refresh indicator that must not blank the screen:

```dart
final articles = ref.watch(articlesProvider);
return Stack(children: [
  if (articles.value case final list?) ArticleList(list),
  if (articles.isLoading) const LinearProgressIndicator(),
]);
```

`unwrapPrevious()` strips the retained previous value, giving the raw state for when you
deliberately want "loading means blank".

## `AsyncValue.guard`

```dart
state = await AsyncValue.guard(() => repository.save(draft));
```

```dart
static Future<AsyncValue<ValueT>> guard<ValueT>(
  Future<ValueT> Function() future, [
  bool Function(Object) test,
])
```

`guard` returns `AsyncData` on success and `AsyncError(error, stackTrace)` on failure, preserving
the original stack trace. The optional second positional argument is a predicate: errors it
rejects are rethrown rather than captured, which is how you let programming errors escape while
still capturing I/O failures.

```dart
state = await AsyncValue.guard(
  () => repository.save(draft),
  (error) => error is! StateError,   // bugs propagate; network failures become AsyncError
);
```

```dart
// Wrong — loses the stack trace, and catches errors it should not.
try {
  await repository.save(draft);
  state = AsyncValue.data(draft);
} catch (e) {
  state = AsyncValue.error(e, StackTrace.current);
}

// Right
state = await AsyncValue.guard(() async {
  await repository.save(draft);
  return draft;
});
```

## Automatic retry

New in 3.0 and **on by default**: a provider that throws during initialisation is retried with
exponential backoff — up to 10 retries, starting at 200 ms and doubling to a 6.4 s ceiling (so a
provider that never succeeds keeps failing for roughly 38 s). The `AsyncError` stays visible
between attempts with `retrying == true`.

The hook is a `Retry` function, `Duration? Function(int retryCount, Object error)`; returning
`null` stops retrying.

```dart
Duration? apiRetry(int retryCount, Object error) {
  if (error is ProviderException) return null;   // upstream already failed and retried
  if (error is HttpException && error.statusCode == 404) return null;
  if (retryCount >= 3) return null;
  return Duration(milliseconds: 200 * (1 << retryCount));
}

final articlesProvider = FutureProvider<List<Article>>(retry: apiRetry, (ref) async => ...);
```

Set it globally when the app-wide policy differs from the default:

```dart
ProviderScope(retry: apiRetry, child: const MyApp());
// or, for a disabled default:
ProviderScope(retry: (retryCount, error) => null, child: const MyApp());
```

Review rules:

- Anything non-idempotent (a payment, a POST) must not retry. Either put it in a notifier method
  — methods are not retried, only provider initialisation is — or pass `retry: (_, __) => null`.
- Do not retry 4xx. A 404 retried ten times is ten wasted round trips and a half-minute spinner.
- `await ref.read(p.future)` waits through the entire retry sequence. A test that awaits a
  deliberately failing provider waits out all ten backoffs — roughly 38 s — unless retry is
  disabled in the test container.
- `ProviderContainer.defaultRetry` is the built-in policy if you need to compose with it.

## `ProviderException`

When a provider rethrows the failure of a provider it watched, Riverpod wraps it in a
`ProviderException` so you can tell "I failed" from "my dependency failed". Unwrap with
`.exception`:

```dart
try {
  ref.read(derivedProvider);
} on ProviderException catch (e) {
  if (e.exception is SocketException) { /* the upstream network error */ }
}
```

The default retry policy deliberately skips `ProviderException` and `Error`, because retrying a
wrapper would multiply the upstream provider's own retries.

## Error surfaces in the UI

- Render errors from `AsyncError`, never from a `try/catch` around `ref.watch`. Watching does not
  throw at a point you can catch usefully.
- Give every error branch a retry affordance: `onPressed: () => ref.invalidate(theProvider)`.
- Log with the stack trace. `AsyncError` carries `stackTrace`; dropping it makes Crashlytics
  reports useless.
- Do not surface raw exception text to users. Map to a message in the presentation layer; the
  Firebase-specific mapping lives in `flutter-firebase-contract`.
- Transient errors from an action (a failed save) belong in a snackbar via `ref.listen`, not in
  the page body. Errors from the page's own data belong in the body. See `widgets.md`.

## Offline persistence (experimental)

`persist()` lets an `AsyncNotifier` restore its last value from a local store before the network
answers; `isFromCache` then reports `true`. The adapter is `riverpod_sqflite` (`JsonSqFliteStorage`),
the notifier mixes in `Persistable`, and `persist()` is called inside `build()` with a key plus
`encode`/`decode` functions and a `cacheTime` (default two days). Both the API and the package are
experimental within 3.x — say so whenever you recommend it, and check the current signature
against the package docs before writing a call.

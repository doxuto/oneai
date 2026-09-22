# Auth and App Check

`firebase_auth` 6.7.0 and `firebase_app_check` 0.4.8. Both are inputs to the callable contract: Auth decides what `request.auth` contains on the server, App Check decides whether the request is allowed to reach the handler at all. Sign-in UI, rules, and custom-claim minting are elsewhere — rules and claims are `firebase-skill` → `firebase-security-pro`.

## The token the app never sends

The SDK attaches the current user's ID token and the current App Check token to every callable automatically. You never build an `Authorization` header and you never put a `uid` in the request body — the server reads `request.auth.uid`. A `uid` field in a request is either ignored (confusing) or trusted (a security bug).

A signed-out call simply goes out without a token; the server sees `request.auth == null` and throws `unauthenticated`. Do not pre-check `FirebaseAuth.instance.currentUser` in the repository and throw locally: the server is the source of truth and the UX path is the same.

## Which auth stream

| Stream | Fires on | Use for |
|---|---|---|
| `authStateChanges()` | sign-in, sign-out | Routing. The one the router watches. |
| `idTokenChanges()` | sign-in, sign-out, **and every ID token refresh** | Anything that must react to a new token — for example re-reading custom claims |
| `userChanges()` | everything `idTokenChanges` does, plus local profile mutations (`updateDisplayName`, `updatePhotoURL`, `reload`) | Showing the user's own profile |

All three are `Stream<User?>`.

```dart
final authStateProvider = StreamProvider<User?>(
  (ref) => FirebaseAuth.instance.authStateChanges(),
);

final currentUidProvider = Provider<String>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) throw StateError('No signed-in user in this scope');
  return user.uid;
});
```

- Watch `authStateChanges()` for the router and nothing else. `idTokenChanges()` fires roughly hourly on token refresh; a router that rebuilds on it thrashes.
- Watch `userChanges()` only where a profile edit must show immediately. It fires for local mutations that no other stream reports.
- Never gate navigation on `currentUser` read synchronously at startup: it is `null` until the SDK restores the persisted session, so the app flashes the sign-in screen. Gate on the first emission of `authStateChanges()`.

## Custom claims and forced refresh

Custom claims live in the ID token. After the server calls `setCustomUserClaims`, the app keeps using its cached token — up to an hour — and the server keeps seeing the old claims.

```dart
Future<void> refreshClaims() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;
  await user.getIdTokenResult(true);   // forceRefresh
}

Future<Map<String, dynamic>> readClaims() async {
  final result = await FirebaseAuth.instance.currentUser!.getIdTokenResult();
  return result.claims ?? const {};
}
```

- `getIdTokenResult([bool forceRefresh = false])` — the parameter is positional, not named. `getIdToken([bool forceRefresh = false])` has the same shape and returns `Future<String?>`.
- Force a refresh immediately after any callable whose job is to change a claim (upgrade to paid, accept an invite, grant a role), then call the dependent function. Otherwise the very next call fails `permission-denied` for no visible reason.
- Better still: have the server return the new entitlement in the callable's response so the UI can update without waiting on a token round trip, and force the refresh in the background.
- Do not parse the JWT yourself. `IdTokenResult.claims` is already decoded.
- Claims are a server-side write. The rules and the minting logic belong to `firebase-skill` → `firebase-security-pro`.

## Anonymous accounts and linking

```dart
Future<void> ensureSignedIn() async {
  if (FirebaseAuth.instance.currentUser == null) {
    await FirebaseAuth.instance.signInAnonymously();
  }
}

Future<void> linkWithGoogle(AuthCredential credential) async {
  final user = FirebaseAuth.instance.currentUser!;
  try {
    await user.linkWithCredential(credential);
  } on FirebaseAuthException catch (e) {
    switch (e.code) {
      case 'credential-already-in-use':
        // The destination account already exists. Sign in to it and migrate or
        // discard the anonymous data — decide this deliberately, it is data loss.
        break;
      case 'provider-already-linked':
        break;
      default:
        rethrow;
    }
  }
}
```

- An anonymous user has a real `uid` and a real token, so `request.auth` is populated and callables work. The server distinguishes them via `request.auth.token.firebase.sign_in_provider == 'anonymous'` and throws `permission-denied` with `details.reason == 'anonymous'` for actions that need a permanent account. The app maps that to "link your account", not to the sign-in screen — see `error-mapping.md`.
- `linkWithCredential` preserves the `uid`, so everything under `users/{uid}` survives. Signing out of the anonymous account and signing in fresh does not: that is a new `uid` and the old data is orphaned.
- `credential-already-in-use` is the case that gets skipped in review. There is no automatic merge; the app has to choose.
- Anonymous accounts are deleted by Firebase after 30 days of inactivity when the automatic-cleanup setting is on. Do not treat an anonymous `uid` as durable identity.

## App Check

`FirebaseAppCheck.instance.activate` is called **after** `Firebase.initializeApp` — the opposite of the native iOS rule, where the provider factory must be installed before `FirebaseApp.configure()`.

The current signature carries both the old enum parameters and the newer provider-class parameters:

```dart
Future<void> activate({
  @Deprecated('Use providerWeb instead.') WebProvider? webProvider,
  WebProvider? providerWeb,
  @Deprecated('Use providerAndroid instead.') AndroidProvider androidProvider = AndroidProvider.playIntegrity,
  @Deprecated('Use providerApple instead.') AppleProvider appleProvider = AppleProvider.deviceCheck,
  AndroidAppCheckProvider providerAndroid = const AndroidPlayIntegrityProvider(),
  AppleAppCheckProvider providerApple = const AppleDeviceCheckProvider(),
  WindowsAppCheckProvider providerWindows = const WindowsDebugProvider(),
});
```

`androidProvider`, `appleProvider` and `webProvider` are deprecated and will be removed in a future major release. Write new code against the provider classes.

| Platform | Release provider | Debug provider |
|---|---|---|
| iOS / macOS | `AppleAppAttestProvider()` or `AppleAppAttestWithDeviceCheckFallbackProvider()` | `AppleDebugProvider({String? debugToken})` |
| Android | `AndroidPlayIntegrityProvider()` | `AndroidDebugProvider({String? debugToken})` |
| Web | `ReCaptchaEnterpriseProvider(siteKey)` / `ReCaptchaV3Provider(siteKey)` | `WebDebugProvider()` |
| Windows | — | `WindowsDebugProvider()` |

App Attest requires iOS 14 / macOS 14 or newer; `AppleAppAttestWithDeviceCheckFallbackProvider` falls back to DeviceCheck where it is unavailable. The deprecated enums are `AppleProvider.{debug, deviceCheck, appAttest, appAttestWithDeviceCheckFallback}` and `AndroidProvider.{debug, playIntegrity}`.

```dart
await FirebaseAppCheck.instance.activate(
  providerApple: kDebugMode
      ? const AppleDebugProvider()
      : const AppleAppAttestWithDeviceCheckFallbackProvider(),
  providerAndroid: kDebugMode
      ? const AndroidDebugProvider()
      : const AndroidPlayIntegrityProvider(),
);
```

Other members:

| Member | Signature |
|---|---|
| `getToken` | `Future<String?> getToken([bool? forceRefresh])` |
| `getLimitedUseToken` | `Future<String> getLimitedUseToken()` |
| `setTokenAutoRefreshEnabled` | `Future<void> setTokenAutoRefreshEnabled(bool)` |
| `onTokenChange` | `Stream<String?>` |

You do not normally call `getToken` — the plugins attach the token themselves. Call it only to debug whether attestation is working at all.

## Limited-use tokens

A replay-protected callable — the server sets `consumeAppCheckToken: true` — needs the client to send a single-use token:

```dart
final redeemCode = functions.httpsCallable(
  Fn.redeemCode,
  options: const HttpsCallableOptions(limitedUseAppCheckToken: true),
);
```

- Each such call fetches a fresh token from the App Check backend: an extra round trip and extra quota. Use it for purchases, redemptions, invite acceptance and account deletion — not for reads.
- Mismatch in either direction is a bug. Server consumes but client sends a normal token: the call fails. Client sends a limited-use token but the server does not consume it: the round trip is wasted and replay protection is imaginary.
- `limitedUseAppCheckToken` is a per-callable option, not a global setting.

## What breaks when App Check is enforced

Symptom: every callable fails `unauthenticated` while the user is demonstrably signed in. Work through this list before touching anything else.

1. Debug builds must use a debug provider and the printed debug token must be registered in the Firebase console, per app, per platform. A simulator and a physical device have different debug tokens.
2. A reinstall, a wiped simulator, or a new developer machine produces a new debug token. Register it again.
3. `AppleDebugProvider`/`AndroidDebugProvider` accept a `debugToken` so CI can pass a pre-registered token instead of reading it from logs.
4. Play Integrity needs the app's signing certificate SHA-256 registered in the Firebase console — a debug-signed APK attests as a different app and fails.
5. App Attest does not work on the iOS simulator. Use the debug provider there.
6. The Functions emulator does not enforce App Check, so "it works against the emulator" says nothing about a deployed function.
7. App Check enforcement is toggled per product in the console. Turning it on for Cloud Functions and forgetting Firestore, or the reverse, produces failures in exactly one half of the app.

Never ship a debug provider in a release build. Gate on `kDebugMode`, not on a `--dart-define` that someone can forget.

## Does not exist / common mistakes

- Calling `FirebaseAppCheck.instance.activate` before `Firebase.initializeApp` — that is the native iOS ordering; in Dart it needs an initialised app.
- `AppCheck.setAppCheckProviderFactory(...)` — Swift API, no Dart equivalent.
- `appleProvider: AppleProvider.appAttest` in new code — deprecated; use `providerApple: const AppleAppAttestProvider()`.
- `AndroidProvider.safetyNet` — SafetyNet is gone; the Android enum has exactly `debug` and `playIntegrity`.
- `user.getIdTokenResult(forceRefresh: true)` — the parameter is positional: `getIdTokenResult(true)`.
- Reading `currentUser` synchronously at startup to decide the first route — it is null until the session is restored.
- Watching `idTokenChanges()` from the router — rebuilds on every hourly token refresh.
- Sending `uid` in a callable request — the server must use `request.auth.uid`.
- Calling a claim-dependent function immediately after the claim-granting one without a forced refresh — `permission-denied` with no visible cause.
- `limitedUseAppCheckToken: true` on every callable "for safety" — doubles latency and burns App Check quota.
- Treating an `unauthenticated` failure as "show the sign-in screen" without checking App Check in debug — sends a signed-in user to a login form that cannot fix anything.

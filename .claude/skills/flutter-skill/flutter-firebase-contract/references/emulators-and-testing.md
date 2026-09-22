# Emulators and testing

Running the Flutter app against the Firebase Emulator Suite, and deciding what is tested with a fake, what against the emulator, and what not at all. Running and seeding the suite itself, plus server-side unit and rules tests, is `firebase-skill` → `firebase-testing-pro`. Widget/golden/integration mechanics are `flutter-testing-pro`.

## Wiring the emulators

All three calls take `(String host, int port)` and are made once, after `Firebase.initializeApp` and before any request.

| Product | Call | Default port |
|---|---|---|
| Functions | `FirebaseFunctions.instanceFor(region: r).useFunctionsEmulator(host, port, {bool automaticHostMapping = true})` | 5001 |
| Firestore | `FirebaseFirestore.instance.useFirestoreEmulator(host, port, {bool sslEnabled = false, bool automaticHostMapping = true})` | 8080 |
| Auth | `FirebaseAuth.instance.useAuthEmulator(host, port, {bool automaticHostMapping = true})` | 9099 |

```dart
Future<void> connectEmulators({String host = 'localhost'}) async {
  FirebaseFunctions.instanceFor(region: kRegion).useFunctionsEmulator(host, 5001);
  FirebaseFirestore.instance.useFirestoreEmulator(host, 8080);
  await FirebaseAuth.instance.useAuthEmulator(host, 9099);
}
```

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  const useEmulator = bool.fromEnvironment('USE_FIREBASE_EMULATOR');
  if (useEmulator) {
    await connectEmulators(
      host: const String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost'),
    );
  }

  runApp(const ProviderScope(child: MyApp()));
}
```

```bash
flutter run --dart-define=USE_FIREBASE_EMULATOR=true
flutter run --dart-define=USE_FIREBASE_EMULATOR=true --dart-define=EMULATOR_HOST=192.168.1.42
```

Gate on a `--dart-define`, not on `kDebugMode` alone: debug builds that talk to the real dev project are a normal thing to want.

## Host per platform

`automaticHostMapping` defaults to `true` and rewrites `localhost` / `127.0.0.1` to `10.0.2.2` on Android, because that is how the Android emulator reaches the host machine. That covers the common case; the rest does not.

| Where the app runs | Host to pass | Notes |
|---|---|---|
| Android emulator | `localhost` | Remapped to `10.0.2.2` automatically |
| iOS simulator | `localhost` | Shares the host's network stack |
| macOS desktop | `localhost` | Needs the network-client entitlement |
| Physical device (either OS) | The host machine's LAN IP, e.g. `192.168.1.42` | Also set `"host": "0.0.0.0"` for each emulator in `firebase.json`, or it binds to loopback and the device cannot reach it |
| Web | `localhost` | Separate delegate; re-verify |

Pass the host from a `--dart-define` so a physical-device run does not need a code edit. Setting `automaticHostMapping: false` is only correct when you are deliberately passing an address that must not be rewritten.

## Demo projects

`Firebase.initializeApp` accepts `demoProjectId`, which initialises the app with placeholder options (`apiKey: '12345'`, `projectId: <the id>`) and **overrides** any `options` argument. By convention the id starts with `demo-`.

```dart
await Firebase.initializeApp(demoProjectId: 'demo-myapp');
await connectEmulators();
```

Use it for an emulator-only entry point — a `main_emulator.dart` or an integration-test harness — where there should be no path to a real project at all. Anything that leaks past the emulator wiring then fails loudly instead of writing to production.

## Seeding and running

```bash
firebase emulators:start --import=./seed --export-on-exit=./seed
```

Run the whole suite, not one emulator. A Functions emulator with a real Firestore behind it writes to production; an Auth emulator without a Functions emulator produces tokens the deployed function rejects. `firebase.json` and the seeding workflow belong to `firebase-skill` → `firebase-testing-pro`.

What the emulator does not reproduce, and therefore cannot tell you:

| Not reproduced | Consequence |
|---|---|
| App Check enforcement | "Works against the emulator" says nothing about a deployed `enforceAppCheck: true` function |
| Composite indexes | Index errors appear only against a real project — see `firestore-streams.md` |
| Cold starts, region latency, real timeouts | Timeout tuning must be measured against the real deployment |
| Quotas, billing, rate limits | `resource-exhausted` paths need a dev project |
| Real FCM delivery | The emulator does not deliver push to devices |
| Production security rules under real claims | Rules tests belong on the server side |

The Auth emulator also accepts tokens the real backend would reject; do not read "the function saw my `uid`" as proof that auth is wired correctly.

## What to test where

| Layer | How | Why |
|---|---|---|
| `fromJson`/`toJson` of every request and response | Plain `dart test` against literal JSON maps copied from a real response | Catches the `as double`, `as List<String>` and nullability traps with no Firebase at all |
| `ApiFailure.fromFunctions` mapping | Plain `dart test` constructing `FirebaseFunctionsException` directly | One test per row of the table in `error-mapping.md` |
| Notifiers and widgets | `flutter_test` with the repository provider overridden by a fake | No network, no emulator, deterministic, fast |
| Repository against real callables | Integration test with `integration_test`, app pointed at the emulator suite | Proves the wiring: region, name, encoding, decoding, error codes |
| Security rules | Server side, `@firebase/rules-unit-testing` | `firebase-skill` → `firebase-security-pro` |

The fake goes in at the repository interface, never at `FirebaseFunctions`:

```dart
await tester.pumpWidget(
  ProviderScope(
    overrides: [
      notesRepositoryProvider.overrideWithValue(
        FakeNotesRepository(onCreate: (_) async => throw const TransientFailure()),
      ),
    ],
    child: const MyApp(),
  ),
);
```

Mocking `FirebaseFunctions` means mocking `HttpsCallable` and `HttpsCallableResult` and re-implementing the plugin's decoding, which is exactly the code you are trying not to trust. See `riverpod-integration.md` for the full fake and `riverpod-pro` → `references/testing.md` for override mechanics.

## A contract test worth having

One integration test per callable, run against the emulator in CI, that sends a realistic request and decodes the response:

```dart
testWidgets('createNote round-trips against the emulator', (tester) async {
  await Firebase.initializeApp(demoProjectId: 'demo-myapp');
  await connectEmulators();
  await FirebaseAuth.instance.signInAnonymously();

  final repo = FirebaseNotesRepository(
    functions: FirebaseFunctions.instanceFor(region: kRegion),
    firestore: FirebaseFirestore.instance,
    uid: FirebaseAuth.instance.currentUser!.uid,
  );

  final response = await repo.createNote(
    const CreateNoteRequest(title: 'Hello', tags: ['a']),
  );

  expect(response.id, isNotEmpty);
  expect(response.createdAt.isUtc, isTrue);
  expect(response.visibility, isNot(NoteVisibility.unknown));
});
```

That single assertion set catches a renamed field, a changed date format, a new enum value, a wrong region, and a response type the app cannot decode — the five ways a contract actually breaks. `visibility != unknown` is the cheapest possible detector for "the server added an enum case".

## What not to test against real Firebase

- Anything in CI that writes to a project a human also uses.
- Error-mapping tests. Provoking a real `resource-exhausted` costs money and is slow; construct the exception.
- Widget behaviour. A widget test that reaches the network is not a widget test.
- Retry and backoff. Inject the sleep function (see `error-mapping.md`) and keep the test instant.
- Push delivery end to end. Verify the token registration callable and the tap handling separately; real delivery is a manual check on a device.
- Anything that depends on a production custom claim. Mint the claim in the Auth emulator instead.

## Does not exist / common mistakes

- `useFunctionsEmulator` after the first call — configure the instance once, at startup.
- Pointing Functions at the emulator but leaving Firestore on production — the callable runs locally and writes to the live database.
- `localhost` from a physical device — nothing listens there. Use the LAN IP and bind the emulators to `0.0.0.0`.
- `10.0.2.2` hard-coded in the Dart source — `automaticHostMapping` already does that for the Android emulator and the constant is wrong everywhere else.
- `FirebaseFunctions.instance.useFunctionsEmulator(...)` while the app calls `instanceFor(region: ...)` — two different instances; the configured one is not the one being used.
- Expecting App Check enforcement to fail in the emulator — it does not enforce.
- Treating a green emulator run as proof that indexes exist.
- Mocking `FirebaseFunctions` instead of the repository.
- `Firebase.initializeApp(demoProjectId: ...)` together with real `options` and expecting the options to win — `demoProjectId` overrides them.
- Leaving `--dart-define=USE_FIREBASE_EMULATOR=true` in a release build script.

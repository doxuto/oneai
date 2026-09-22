# Setup

Everything that must be true before the first callable or listener runs: the generated options file, the order of work in `main()`, one configuration per flavour, and the plugin version matrix. Most "Firebase works on my machine" bugs are one of these four.

## Version matrix — verified on pub.dev, 2026-09-22

| Package | Version | Requires |
|---|---|---|
| `firebase_core` | 4.15.0 | — |
| `cloud_functions` | 6.5.0 | `firebase_core ^4.14.0` |
| `cloud_firestore` | 6.10.0 | `firebase_core ^4.14.0` |
| `firebase_auth` | 6.7.0 | `firebase_core ^4.14.0` |
| `firebase_messaging` | 16.7.0 | `firebase_core ^4.14.0` |
| `firebase_app_check` | 0.4.8 | `firebase_core ^4.14.0` |
| `flutterfire_cli` | 1.4.1 | installed globally |

Reconfirm each on pub.dev before pinning: the FlutterFire packages ship together roughly weekly and a partial bump produces a `firebase_core` version conflict at `pub get`. Bump the whole block or none of it.

```yaml
environment:
  sdk: ^3.13.0
  flutter: ">=3.47.0"

dependencies:
  firebase_core: ^4.15.0
  cloud_functions: ^6.5.0
  cloud_firestore: ^6.10.0
  firebase_auth: ^6.7.0
  firebase_messaging: ^16.7.0
  firebase_app_check: ^0.4.8
  flutter_riverpod: ^3.4.3
```

`firebase_app_check` is still below 1.0, so `^0.4.8` means `>=0.4.8 <0.5.0`. A `0.5.0` release is a breaking change that will not be picked up by `pub upgrade` — read its changelog when it lands.

## `flutterfire configure`

```bash
dart pub global activate flutterfire_cli
flutterfire configure --project=my-project-id
```

The generated `lib/firebase_options.dart` contains a `DefaultFirebaseOptions` class with a `currentPlatform` getter and one `FirebaseOptions` constant per platform. It is generated code: commit it, never edit it, regenerate it whenever a platform, bundle id, package name, or Firebase project changes.

Flags worth knowing (verified against `flutterfire_cli` `config.dart`):

| Flag | Abbr | Purpose |
|---|---|---|
| `--project` | `-p` | Firebase project alias or id |
| `--out` | `-o` | Dart output path, default `lib/firebase_options.dart` |
| `--platforms` | | Comma-separated: `android,ios,macos,web,linux,windows` |
| `--ios-bundle-id` | `-i` | iOS bundle identifier |
| `--android-package-name` | `-a` | Android package name |
| `--ios-out` | | Where to write `GoogleService-Info.plist` — the flavour flag |
| `--android-out` | | Where to write `google-services.json` — the flavour flag |
| `--ios-build-config` | | Xcode build configuration to attach the plist to |
| `--ios-target` | | Xcode target to attach the plist to |
| `--yes` | `-y` | Non-interactive; accept detected defaults |
| `--token` | `-t` | CI token from `firebase login:ci` |
| `--service-account` | | Path to a service-account JSON, for CI |

`--android-app-id` is deprecated in favour of `--android-package-name`.

## Initialisation order in `main()`

```dart
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await FirebaseAppCheck.instance.activate(
    providerApple: kDebugMode
        ? const AppleDebugProvider()
        : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    providerAndroid: kDebugMode
        ? const AndroidDebugProvider()
        : const AndroidPlayIntegrityProvider(),
  );

  // Emulator wiring, if any — see emulators-and-testing.md.

  runApp(const ProviderScope(child: MyApp()));
}
```

Rules that follow from that order:

1. `WidgetsFlutterBinding.ensureInitialized()` comes first. Without it, the platform channels `Firebase.initializeApp` uses are not ready.
2. `Firebase.initializeApp` is awaited before anything touches `FirebaseFunctions`, `FirebaseFirestore`, `FirebaseAuth` or `FirebaseMessaging`.
3. App Check is activated **after** `initializeApp`, not before. This is the opposite of the native iOS SDK, where the provider factory must be installed before `FirebaseApp.configure()`. Do not port that rule into Dart.
4. Emulator calls come after `initializeApp` and before the first request.
5. `runApp` is last, so no widget can build against a half-initialised app.

Never call `Firebase.initializeApp()` a second time with the default name — it throws `[core/duplicate-app]`. If you need to guard, check `Firebase.apps.isEmpty`.

## Multiple flavours and projects

One Firebase project per environment, one generated options file per environment, selected at compile time — not at runtime from a map.

```bash
flutterfire configure \
  --project=myapp-dev \
  --out=lib/firebase_options_dev.dart \
  --ios-bundle-id=com.example.myapp.dev \
  --android-package-name=com.example.myapp.dev \
  --ios-out=ios/config/dev/GoogleService-Info.plist \
  --android-out=android/app/src/dev/google-services.json \
  --ios-build-config=Debug-dev

flutterfire configure \
  --project=myapp-prod \
  --out=lib/firebase_options_prod.dart \
  --ios-bundle-id=com.example.myapp \
  --android-package-name=com.example.myapp \
  --ios-out=ios/config/prod/GoogleService-Info.plist \
  --android-out=android/app/src/prod/google-services.json \
  --ios-build-config=Release
```

Pick the options object at the entry point, one `main_<flavour>.dart` per flavour:

```dart
// lib/main_dev.dart
import 'firebase_options_dev.dart';
import 'bootstrap.dart';

void main() => bootstrap(DefaultFirebaseOptions.currentPlatform);
```

```dart
// lib/bootstrap.dart
Future<void> bootstrap(FirebaseOptions options) async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: options);
  // ...
}
```

Both generated files declare a class named `DefaultFirebaseOptions`, so import exactly one per entry point. Importing both in the same library is a name collision; if you genuinely need both, use an `as` prefix.

- Android picks up `google-services.json` from `android/app/src/<flavour>/` automatically when the flavour name matches the product flavour.
- iOS does **not**. The plist written by `--ios-out` has to be added to the Xcode target and, if it is per-configuration, copied by a build phase. `--ios-build-config` and `--ios-target` make the CLI wire that up; verify the resulting build phase in Xcode rather than assuming.
- `google-services.json` and `GoogleService-Info.plist` are not secrets — they identify the app, they do not authorise it. Security comes from rules and App Check, not from hiding these files. Commit them.

## Platform minimums

| Platform | Minimum | Where |
|---|---|---|
| iOS | 15 | `ios/Podfile` `platform :ios, '15.0'` and the Xcode deployment target |
| Android | API 23 | `android/app/build.gradle(.kts)` `minSdk` |
| macOS | 10.15 | `macos/Podfile` |

Symptoms of getting these wrong: CocoaPods fails at `pod install` with a deployment-target mismatch listing the Firebase pods, or the Android build fails with `uses-sdk:minSdkVersion N cannot be smaller than version 23`. Raise the project minimum; do not override the manifest.

Other platform gotchas:

- Android needs `com.google.gms.google-services` applied in `android/app/build.gradle(.kts)`; `flutterfire configure` adds it by default. If a build suddenly cannot find the default `FirebaseApp` on Android only, that plugin block is missing.
- Enable the "Push Notifications" capability and "Background Modes → Remote notifications" in Xcode before touching `firebase_messaging`. See `messaging.md`.
- macOS additionally needs the App Sandbox network entitlements (`com.apple.security.network.client`) or every call fails with an opaque network error.
- Web is a separate delegate for every plugin. If the app ships web, re-verify decoding and emulator behaviour there; the rules in this skill are written for the method-channel platforms.

## Does not exist / common mistakes

- `Firebase.initializeApp()` with no `options` on a plain Flutter app — works only where a native config file is present and linked, and silently uses the wrong project on platforms where it is not. Always pass `DefaultFirebaseOptions.currentPlatform`.
- Editing `firebase_options.dart` by hand — the next `flutterfire configure` overwrites it.
- One `firebase_options.dart` with a runtime `if (flavor == 'dev')` switch — ships dev credentials inside the production binary and makes the wrong project one typo away.
- Calling `FirebaseFirestore.instance` at a top-level `final` initialiser — evaluated lazily in Dart, but easy to trip by a `main()` that touches it before `initializeApp` resolves.
- `await Firebase.initializeApp()` inside a widget's `initState` — the first frame can already have built something that reads Firebase.
- Setting up App Check before `Firebase.initializeApp` because that is the iOS rule — in Dart it throws, because `activate` needs an initialised app.
- Bumping `cloud_firestore` alone and leaving `firebase_core` pinned — `pub get` fails or, worse, resolves to an old `firebase_core` and crashes natively.

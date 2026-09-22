# Flutter Skills for Claude Code

**5 skills for building a Flutter app with Claude Code** — the Dart 3.13 language, the widget layer on Flutter 3.47, Riverpod 3 state management, the test suite, and the Firebase contract that connects the app to its backend.

This is the Flutter sibling of [`ios-ai-skill`](https://github.com/doxuto/iOS-AI-SKILL) and [`firebase-skill`](https://github.com/doxuto/Server-AI-SKILL). `flutter-firebase-contract` is the Dart mirror of `firebase-skill`'s `firebase-ios-contract` — same function names, same envelope, same error table — so a Flutter client and an iOS client can sit on one backend without the two halves drifting. Anything server-side hands off to `firebase-skill` rather than being restated here.

Install into `~/.claude/skills/` and Claude loads the matching skill automatically based on what you ask for.

## The skills

### Language and UI

| Skill | What it does |
|---|---|
| **`dart-pro`** | The Dart 3.13 language itself — sound null safety and the field-promotion rules, records and the full pattern grammar, class modifiers and sealed hierarchies, extension types, primary constructors, async and streams, error modelling, `analysis_options.yaml`, and the removed/renamed APIs models keep emitting |
| **`flutter-widgets-pro`** | Widget/Element/RenderObject and what `const` and keys actually do, the `State` lifecycle and controller ownership, the constraints model and how to read layout errors, slivers, Material 3 on the new `material_ui` package, go_router 18, rebuild performance, forms and focus, accessibility |

### State and data

| Skill | What it does |
|---|---|
| **`riverpod-pro`** | Riverpod 3 — the provider types that survived, codegen with `riverpod_annotation` 4.x, `Notifier`/`AsyncNotifier`, the unified `Ref` and its lifecycle, sealed `AsyncValue` and automatic retry, consumers, `ProviderContainer.test()`, feature-first architecture and `riverpod_lint`, plus a 2 → 3 migration table |
| **`flutter-firebase-contract`** | The Flutter half of the backend contract — `httpsCallable` and streaming callables, mirroring the server's zod schemas in Dart, `FirebaseFunctionsException` mapped to a sealed failure type, `snapshots()` with `withConverter`, App Check and auth tokens, FCM, the emulator suite |

### Testing

| Skill | What it does |
|---|---|
| **`flutter-testing-pro`** | `flutter_test` — what to test and what not to, the four pump variants and when each hangs, finders and matchers, `fakeAsync` and `tester.runAsync`, hand-written fakes over mocks, goldens and why they differ across machines, `integration_test`, and the twelve recurring causes of flaky Flutter tests |

## Install

Install for every project on your machine:

```bash
git clone git@github.com:doxuto/flutter-skill.git
mkdir -p ~/.claude/skills
cp -R flutter-skill/*/ ~/.claude/skills/
```

Over HTTPS instead, if you have no SSH key set up:

```bash
git clone https://github.com/doxuto/flutter-skill.git
```

Install into a single project, so the skills travel with the repo and your team gets them too:

```bash
cd /path/to/your-app
mkdir -p .claude/skills
cp -R /path/to/flutter-skill/*/ .claude/skills/
```

Verify with `/skills` in Claude Code — all 5 should be listed. Skills load by their `description`, so you never invoke them by name: ask "review this notifier", "why does this ListView overflow", or "write a widget test for the sign-in screen" and the matching skill loads itself.

### Updating

```bash
cd /path/to/flutter-skill
git pull
cp -R ./*/ ~/.claude/skills/
```

`cp -R` overwrites the skill folders in place and leaves any other skills you have alone.

### Staying on a symlink instead

```bash
git clone git@github.com:doxuto/flutter-skill.git ~/dev/flutter-skill
mkdir -p ~/.claude/skills
for skill in ~/dev/flutter-skill/*/; do
  ln -sfn "$skill" ~/.claude/skills/"$(basename "$skill")"
done
```

Each skill is a folder containing `SKILL.md` plus reference files that Claude loads on demand, so an unused reference costs no context.

## How the skills fit together

A typical feature touches several of them, in roughly this order:

1. **`dart-pro`** — model the domain first: sealed state, records where a class would be ceremony, a `Result` type or a deliberate throw.
2. **`flutter-firebase-contract`** — decide the callable's name and the Dart mirror of the server's zod schema before writing either side. The server half is `firebase-skill` → `firebase-ios-contract`.
3. **`riverpod-pro`** — the repository behind a provider, the `AsyncNotifier` that owns the write path, the `StreamProvider` over `snapshots()`.
4. **`flutter-widgets-pro`** — the screen: layout, theming, navigation, focus, and the rebuild scoping that keeps it cheap.
5. **`flutter-testing-pro`** — notifier tests without a tree, widget tests over a faked repository, one integration test for the flow.

On the server side, the callable that `flutter-firebase-contract` describes is written with `firebase-skill` → `firebase-functions-pro`, gated with `firebase-security-pro`, and pushed from `fcm-push-pro`.

## Versions these skills target

| | |
|---|---|
| Flutter | 3.47.5 stable (Dart 3.13.4) |
| Material / Cupertino | `material_ui` 1.3.x, `cupertino_ui` 1.x — decoupled out of the SDK, see below |
| Riverpod | `flutter_riverpod` 3.4.3, `riverpod_annotation` 4.0.7, `riverpod_generator` 4.0.9, `riverpod_lint` 3.1.9 |
| Routing | `go_router` 18.0.x |
| Firebase | `firebase_core` 4.15.0, `cloud_functions` 6.5.0, `cloud_firestore` 6.10.0, `firebase_auth` 6.7.0, `firebase_messaging` 16.7.0, `firebase_app_check` 0.4.8 |
| Testing | `flutter_test` and `integration_test` from the SDK, `mocktail` 1.0.5, `mockito` 5.8.1, `fake_async` 1.3.3, `clock` 1.1.3 |
| Lints | `flutter_lints` 6.0.0 or `very_good_analysis` 11.x |

Where a skill documents an API that arrived in a specific release, it says so, rather than assuming the latest.

## The Material decoupling

Every Material example in this bundle imports `package:material_ui/material_ui.dart`, not `package:flutter/material.dart`. Flutter 3.44 froze the in-framework Material and Cupertino libraries and 3.47 shipped them as standalone packages at 1.0.0. The old imports still compile, but the two libraries declare **distinct types**: a `ThemeData` from `package:flutter/material.dart` cannot be passed where a `material_ui` `ThemeData` is expected, and the resulting error prints the same class name on both sides of "argument type X is not the type X". go_router 18 already depends on `material_ui ^1.0.0`, so an app on current routing is effectively migrated whether it meant to be or not.

Migrate an existing app in one command:

```bash
dart fix --apply --code=migrate_design_widgets
```

`package:flutter/widgets.dart`, `/rendering.dart`, `/services.dart` and `/foundation.dart` are unchanged and still ship in the SDK. Formal deprecation of the in-framework libraries is "scheduled for an upcoming stable release" with no date named, so treat the migration as due rather than urgent — but do not mix the two.

## A note on accuracy

Skills that assert API surface are only as good as their verification. Every Dart, Flutter, Riverpod and FlutterFire symbol in this bundle was checked against dart.dev, api.flutter.dev, riverpod.dev, pub.dev's API reference, or the plugin source. Where an exact flag, parameter or default could not be confirmed, the text says **"verify against the API docs"** next to it instead of guessing a plausible name.

Things that are wrong in circulating Flutter examples and are called out here:

- `AutoDisposeNotifier`, `FutureProviderRef` and the other typed refs — gone in Riverpod 3. One `Notifier`, one `Ref`.
- `StateProvider`, `StateNotifierProvider`, `ChangeNotifierProvider`, `StateNotifier` — alive only behind `package:flutter_riverpod/legacy.dart`. New code uses `NotifierProvider`.
- `AsyncValue.valueOrNull` — renamed to `.value` in Riverpod 3.
- `riverpod_lint` with a `custom_lint` dev dependency and an `analyzer: plugins:` block — Riverpod 3 declares it under a top-level `plugins:` key instead.
- `Scaffold.of(context).showSnackBar` — `ScaffoldMessenger.of(context).showSnackBar`.
- `MediaQuery.of(context).textScaleFactor` — `MediaQuery.textScalerOf(context)` and `TextScaler`.
- `Color.withOpacity` — `.withValues(alpha: …)`.
- `find.byText` — the finder is `find.text`. `pumpAndSettleUntil` and `findsExactlyNWidgets` do not exist at all.
- `HttpsCallableOptions(requireLimitedUseAppCheckTokens: …)` — that is the Swift spelling. Dart's parameter is `limitedUseAppCheckToken`.
- `FirebaseFirestore.enablePersistence()` — removed in cloud_firestore 6.x; use `Settings(persistenceEnabled: …)`.
- `FirebaseAppCheck.instance.activate(appleProvider: …, androidProvider: …)` — those enum parameters are deprecated in 0.4.x; the current form is `providerApple: AppleAppAttestProvider()` / `providerAndroid: AndroidPlayIntegrityProvider()`.
- `golden_toolkit` — discontinued since 0.15.0 (Feb 2023).

Two things commonly described as removed that are **not**, as of 3.47: `WillPopScope` (deprecated since 3.12, still present, but it breaks Android predictive back — use `PopScope`) and `TestWidgetsFlutterBinding.window` (deprecated, still present; size and padding moved to `tester.view`, while text scale, locale and brightness moved to `tester.platformDispatcher`).

### Known soft spots

These are flagged rather than hidden. Each is written in the skills with an explicit verify-it marker:

- `BackgroundIsolateBinaryMessenger` setup for plugin calls from a background isolate.
- `family.overrideWith2`'s exact signature (the 3.2.0 deprecation of `family.overrideWith` is confirmed; the replacement's signature is not).
- `UnmountedRefException` — named in Riverpod's 3.0 migration guide but absent from the published class listing, so the skills describe the behaviour without naming the class.
- The Firestore `whereIn` / `arrayContainsAny` value cap, and web-platform parity for the FlutterFire delegates.
- `go_router` 18.0.1's exact SDK constraint (18.0.0's changelog says Flutter 3.44 / Dart 3.12).

If you extend these skills, verify against primary sources before adding an API, and prefer saying "I'm not sure this exists" over writing a plausible-looking name.

## Credits

Bundle written and maintained by **[doxuto](https://github.com/doxuto)**.

## License

MIT. Copyright © doxuto.

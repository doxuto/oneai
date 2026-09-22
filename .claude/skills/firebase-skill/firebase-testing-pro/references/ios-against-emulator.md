# iOS against the emulator

Layer 5. The iOS app (Swift, SwiftUI, TCA) points every Firebase service at the local Emulator Suite in DEBUG, behind a launch argument, so the same build can hit the dev project or the emulator without recompiling. XCUITest launches the app with that argument and relies on `--import ./seed` for known users and documents. How to write the UI tests themselves is `xcuitest-pro`'s job; this file defines the Firebase side of the contract.

## Emulator gate — one place, before any service is touched

```swift
// App/FirebaseBootstrap.swift
import FirebaseAppCheck
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseFunctions
import FirebaseStorage
import Foundation

enum FirebaseBootstrap {
  /// Call once from the App's init / AppDelegate before any Firebase service is used.
  static func configure() {
    #if DEBUG
    AppCheck.setAppCheckProviderFactory(DebugAppCheckFactory())   // AppCheckDebugProvider; harmless against the emulator
    #endif
    FirebaseApp.configure()
    #if DEBUG
    if let host = EmulatorConfig.host {
      Self.pointAtEmulator(host: host)
    }
    #endif
  }

  #if DEBUG
  private static func pointAtEmulator(host: String) {
    Auth.auth().useEmulator(withHost: host, port: 9099)

    let settings = Firestore.firestore().settings
    settings.host = "\(host):8080"
    settings.isSSLEnabled = false
    settings.cacheSettings = MemoryCacheSettings()   // no disk cache leaking between test runs
    Firestore.firestore().settings = settings

    Storage.storage().useEmulator(withHost: host, port: 9199)
    Functions.functions(region: "asia-southeast1").useEmulator(withHost: host, port: 5001)
  }
  #endif
}

#if DEBUG
enum EmulatorConfig {
  /// `-useFirebaseEmulator` launch argument turns the gate on; FIREBASE_EMULATOR_HOST overrides the host (LAN IP for a device).
  static var host: String? {
    let info = ProcessInfo.processInfo
    guard info.arguments.contains("-useFirebaseEmulator") else { return nil }
    return info.environment["FIREBASE_EMULATOR_HOST"] ?? "127.0.0.1"
  }
}

final class DebugAppCheckFactory: NSObject, AppCheckProviderFactory {
  func createProvider(with app: FirebaseApp) -> AppCheckProvider? { AppCheckDebugProvider(app: app) }
}
#endif
```

Rules baked into this file:

- `useEmulator` / `settings` calls happen **once**, **before** the first `Auth.auth()`, `Firestore.firestore()`, `Functions.functions()` use. Calling them later throws or is ignored depending on the service.
- `Functions.functions(region:)` must use the **same region string** as the callable's `region` option and as the emulator's route, or you get `.notFound`.
- The whole thing is `#if DEBUG`; Release builds cannot be pointed at an emulator even with the argument present.
- `MemoryCacheSettings()` keeps a previous run's Firestore cache from showing stale seed data.
- Ports match `firebase.json`. If they ever change, change both.

If Auth or Functions traffic to `http://127.0.0.1` is blocked by App Transport Security (ATS error `-1022` in the console), add `NSAppTransportSecurity` → `NSAllowsLocalNetworking = YES` to the Debug Info.plist only. Plain IP addresses are normally exempt from ATS; the key is needed for `.local` hostnames or when a custom Info.plist tightened the defaults.

## Where this lives in a TCA app

Wrap each service in a `@DependencyClient` (see `tca-pro` → `references/dependencies.md`) and let the live value call `Functions.functions(region:)` lazily. `FirebaseBootstrap.configure()` runs in `App.init` — not inside a reducer, not inside a dependency's `liveValue`. The emulator gate is app bootstrap, not a dependency.

```swift
@main
struct SnapToolApp: App {
  init() { FirebaseBootstrap.configure() }
  var body: some Scene { WindowGroup { AppView(store: Store(initialState: AppFeature.State()) { AppFeature() }) } }
}
```

## Running the app against the emulator by hand

1. `firebase emulators:start --only functions,firestore,auth,storage --project demo-snaptool --import ./seed`
2. Xcode scheme → Run → Arguments → add `-useFirebaseEmulator`.
3. Simulator: leave `FIREBASE_EMULATOR_HOST` unset (`127.0.0.1` works — the Simulator shares the Mac's loopback).
4. Physical device: start with `--config firebase.lan.json` (every emulator `host: 0.0.0.0`), add `FIREBASE_EMULATOR_HOST=192.168.1.20` to the scheme's environment, same Wi-Fi.
5. Sign in as `alice@test.dev` / `password` — the Auth emulator accepts any password for imported users only if the export contains a password hash; for the seed script in `emulator-suite.md` it does.

Emulator UI at `http://127.0.0.1:4000` shows the Firestore writes and Functions logs as you tap through.

## XCUITest with the emulator and seed data

```swift
// SnapToolUITests/EmulatorLaunch.swift
import XCTest

extension XCUIApplication {
  /// Launch against the local Emulator Suite. Requires `firebase emulators:start --import ./seed` on the Mac (or the CI job in ci.md).
  static func launchAgainstEmulator(extraArguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-useFirebaseEmulator", "-uiTesting"] + extraArguments
    if let host = ProcessInfo.processInfo.environment["FIREBASE_EMULATOR_HOST"] {
      app.launchEnvironment["FIREBASE_EMULATOR_HOST"] = host   // forwarded from the test runner's scheme
    }
    app.launch()
    return app
  }
}
```

```swift
// SnapToolUITests/CreateNoteFlowTests.swift
import XCTest

final class CreateNoteFlowTests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  func testSignedInUserCreatesNote() throws {
    let app = XCUIApplication.launchAgainstEmulator()
    let screen = SignInScreen(app: app)            // Robot pattern — see xcuitest-pro
      .signIn(email: "alice@test.dev", password: "password")
      .tapNewNote()
      .type(title: "From XCUITest")
      .save()
    XCTAssertTrue(screen.noteCell(titled: "From XCUITest").waitForExistence(timeout: 10))
  }
}
```

Contract with the seed:

| Seed entity | Value | Used by |
|---|---|---|
| user `alice` | `alice@test.dev` / `password`, claims `{ role: "member" }` | happy paths |
| user `bob` | `bob@test.dev` / `password` | sharing / permission-denied paths |
| `users/alice/notes/n1` | `{ title: "Seed note" }` | list screen has one row |
| `users/alice/scans/s1` | `{ status: "done", ocrText: "…" }` | scan detail screen |

Change the seed → update this table → update the UI tests in the same PR.

### Isolation between UI tests

XCUITest cannot call the Admin SDK. Options, cheapest first:

1. **Unique data per test.** Create with a timestamped title; never assert on counts.
2. **Reset the emulator between tests** from the test runner with the emulator's REST endpoint (the runner is a macOS process and can use `URLSession`):
   ```swift
   func resetFirestore() async throws {
     var req = URLRequest(url: URL(string: "http://127.0.0.1:8080/emulator/v1/projects/demo-snaptool/databases/(default)/documents")!)
     req.httpMethod = "DELETE"
     _ = try await URLSession.shared.data(for: req)
   }
   ```
   Then re-import seed by restarting the emulator — slow; prefer option 1.
3. **Test-only callable** `resetTestData` exported only when `process.env.FUNCTIONS_EMULATOR === "true"`, invoked by the app when launched with `-resetTestData`. Never exported in production builds; guard the export at module level.

### Signing in without typing

For flows that are not about sign-in, launch with `-signInAs alice` and let the DEBUG bootstrap call `Auth.auth().signIn(withEmail:password:)` against the emulator before the first screen. Keep the credentials in the test target, not in the app bundle.

## Asserting server side effects from a UI test

Don't. If the test needs to know a Firestore document changed, that is a layer-3 test in `integration-testing.md`. The UI test asserts on what the screen shows after the app's own snapshot listener delivers the change. If the screen has no visible effect, the feature has a UX gap, not a test gap.

## Hand-off

- Robot pattern, waits, flakiness triage, test plans, CI for the iOS side → `xcuitest-pro`.
- Dependency injection of `Functions`, `Auth`, `Firestore` clients into reducers → `tca-pro` (`references/dependencies.md`).
- Typed callables and error mapping in Swift → `firebase-ios-contract`.
- Starting the emulator in the same CI job that runs `xcodebuild test` → `ci.md`.

## Does not exist / common mistakes

- `Functions.functions().useFunctionsEmulator(origin: "http://localhost:5001")` — the old API (iOS SDK < 7); use `useEmulator(withHost:port:)`.
- `Firestore.firestore().useEmulator(withHost:port:)` without `settings.isSSLEnabled = false` — the SDK tries TLS against the plaintext emulator and hangs.
- `Auth.auth().useEmulator(withHost: "http://127.0.0.1", port: 9099)` — host is a bare hostname, no scheme.
- Calling `useEmulator` after a `Firestore.firestore()` read already happened — settings are frozen after first use.
- `localhost` on a physical device — it is the phone. Use the Mac's LAN IP and `host: 0.0.0.0` in the emulator config.
- Expecting App Check enforcement failures in the emulator — App Check is not enforced there; use the debug provider to keep the console quiet and verify enforcement in staging.
- Reusing the real `GoogleService-Info.plist` project id in `--project` — the app's plist project id and the emulator's `--project` should both be `demo-snaptool` for UI tests; a mismatch shows up as `auth/invalid-credential`-style errors or as the Functions emulator logging a token audience warning and treating the caller as unauthenticated. Ship a `GoogleService-Info-Emulator.plist` with `PROJECT_ID = demo-snaptool` selected by the `-useFirebaseEmulator` argument via `FirebaseOptions(contentsOfFile:)` if a mismatch shows up (see `firebase-deploy-pro` → `references/environments.md`).

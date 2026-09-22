# Architecture

## Module split

| Module | Imports GoogleMobileAds? | Contains | Imported by |
|---|---|---|---|
| **AdsCore** (inside the app's core package) | **No** | `AdsConfig`, `AdLedger`, `AdGate`, `AdUnitIDs`, placement enums, `AdEvent` | Everything, incl. tests |
| **AdsClient** interface (same package, or feature layer) | No | Struct of closures: `start`, `showInterstitial`, `showAppOpen`, `showRewarded`, `canRequestAds` | Features |
| **AdsLive** (separate target) | Yes (+ UMP) | Live implementation of the client, preloading, delegates, `paidEventHandler` | **App target only** |
| **AdsUI** (separate target, if native) | Yes | `NativeAdsHost`, `NativeAdPool`, `NativeAdCardView` | **App target only** |
| DesignSystem | No | `NativeAdSlot` view + environment value for the renderer | Features |

Why: features and their test bundles never link Google's SDK; previews and tests render zero
ads by construction; swapping networks touches two targets.

## The gate contract

```
feature event ─▶ AdGate.<format>(config, ledger, adsEntitled, now…) ─▶ .allow / .refuse(reason)
                                                     │ allow
                                                     ▼
                                   AdsClient.show…() ─▶ SDK (preloaded ad or nothing)
                                                     │ shown
                                                     ▼
                                   ledger.recordShown(format, at:)  ─▶ persist
```

Rules:
- The gate is **pure**: no SDK, no `Date()`, no `UserDefaults`. Time and calendar are passed in.
  That's what makes the timing rules testable to the second.
- Check order is fixed: master switch → entitlement → format enabled → format-specific rules.
  Each has its own `Refusal` so analytics can tell them apart.
- If the gate says allow but no ad is loaded, **show nothing** and record `noFill`/`notReady`.
  Never wait for a load on the trigger (late pop-in is a policy violation).
- Record `shown` only when the SDK reports the ad actually presented
  (`adWillPresentFullScreenContent`), and `dismissed` on dismissal — the cooldown starts there.

## The ledger

`AdLedger` is the persisted counter state (JSON in `UserDefaults` is fine; it's not sensitive).
It rolls over per calendar day using the calendar passed in. Mutations:

- `recordSessionStart(at:)` — on cold launch / foreground after a new session boundary
- `recordCompletion()` — every "done" moment, whether or not an ad shows
- `recordShown(_:at:)` — per format
- `recordFullScreenDismissed(at:)`

## Dependency client (TCA example)

`AdShowResult`, `AdEvent`, `AdImpression`, `AdAnalytics` live in `templates/AdsCore/AdEvent.swift`.
The live implementation is `AdsLiveController` (`templates/AdsLive/AdsLiveClient.swift`).

```swift
import Dependencies
import DependenciesMacros

@DependencyClient
public struct AdsClient: Sendable {
    public var apply: @Sendable (AdsConfig) async -> Void
    public var showInterstitial: @Sendable (_ placement: String) async -> AdShowResult = { _ in .notReady }
    public var showAppOpen: @Sendable () async -> AdShowResult = { .notReady }
    /// `userID` goes to ServerSideVerificationOptions for SSV. The server credits, not the app.
    public var showRewarded: @Sendable (_ placement: String, _ userID: String) async -> AdShowResult = { _, _ in .notReady }
    public var clearForAdFreeUser: @Sendable () async -> Void
}

extension AdsClient: TestDependencyKey {
    public static let testValue = AdsClient()
    public static let previewValue = AdsClient(
        apply: { _ in }, showInterstitial: { _ in .notReady }, showAppOpen: { .notReady },
        showRewarded: { _, _ in .notReady }, clearForAdFreeUser: {})
}

// App target only:
extension AdsClient: DependencyKey {
    public static let liveValue: AdsClient = {
        let controller = MainActor.assumeIsolated {
            AdsLiveController(unitIDs: AdUnitIDs(compiled: [/* production IDs */]), analytics: .log)
        }
        return AdsClient(
            apply: { await controller.apply(config: $0) },
            showInterstitial: { await controller.showInterstitial(placement: $0) },
            showAppOpen: { await controller.showAppOpen() },
            showRewarded: { await controller.showRewarded(placement: $0, userID: $1) },
            clearForAdFreeUser: { await controller.clearForAdFreeUser() })
    }()
}
```

For TCA 0.5x without macros, write the struct by hand with `unimplemented(...)` test values.

## The reducer side (the only place that calls the gate)

```swift
case .documentSaved:                       // a "done" moment
    state.adLedger.recordCompletion()
    let decision = AdGate.interstitial(config: state.adsConfig, context: .init(
        ledger: state.adLedger, adsEntitled: state.plan.adsEnabled, now: now, calendar: calendar))
    guard decision.isAllowed else {
        if case let .refuse(reason) = decision { analytics.event(.refused(.interstitial, placement: "documentSaved", reason: reason)) }
        return .none
    }
    return .run { send in
        let shownAt = now
        let result = await ads.showInterstitial("documentSaved")
        await send(.adFinished(.interstitial, result, shownAt: shownAt))
    }

case let .adFinished(format, result, shownAt):
    switch result {
    case .dismissed, .rewardEarnedAndDismissed:
        state.adLedger.recordShown(format, at: shownAt, calendar: calendar)
        state.adLedger.recordFullScreenDismissed(at: now)
    case .notReady, .failed:
        break                                  // nothing shown ⇒ nothing counted
    }
    return .run { [ledger = state.adLedger] _ in await ledgerStore.save(ledger) }
```

`now` and `calendar` come from `@Dependency(\.date.now)` / `@Dependency(\.calendar)` so tests control
time. Persist the ledger after every mutation.

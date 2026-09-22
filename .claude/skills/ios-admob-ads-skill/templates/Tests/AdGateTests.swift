import Foundation
import Testing
@testable import AdsCore   // rename to the module the core files live in

@Suite("AdGate")
struct AdGateTests {
    let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    let t0 = Date(timeIntervalSince1970: 1_800_000_000) // fixed, mid-day UTC

    var on: AdsConfig {
        var c = AdsConfig.safeDefault
        c.enabled = true
        c.native.placements = ["library"]
        return c
    }

    /// A ledger for a returning user well into a session.
    func warmLedger() -> AdLedger {
        var l = AdLedger()
        for _ in 0..<5 { l.recordSessionStart(at: t0.addingTimeInterval(-3600)) }
        l.sessionStartedAt = t0.addingTimeInterval(-600)
        for _ in 0..<5 { l.recordCompletion() }
        return l
    }

    func ctx(_ ledger: AdLedger, at date: Date? = nil, entitled: Bool = true) -> AdGate.Context {
        .init(ledger: ledger, adsEntitled: entitled, now: date ?? t0, calendar: calendar)
    }

    // MARK: Switches

    @Test func safeDefaultIsOff() {
        #expect(AdsConfig.safeDefault.enabled == false)
        #expect(AdsConfig.safeDefault.banner.enabled == false)
        #expect(AdGate.interstitial(config: .safeDefault, context: ctx(warmLedger())) == .refuse(.masterSwitchOff))
    }

    @Test func masterSwitchCheckedBeforeEntitlement() {
        let d = AdGate.rewarded(config: .safeDefault, context: ctx(warmLedger(), entitled: false))
        #expect(d == .refuse(.masterSwitchOff))
    }

    @Test func paidUserNeverSeesAds() {
        let c = ctx(warmLedger(), entitled: false)
        #expect(AdGate.interstitial(config: on, context: c) == .refuse(.notEntitledToAds))
        #expect(AdGate.appOpen(config: on, context: c, secondsInBackground: 999) == .refuse(.notEntitledToAds))
        #expect(AdGate.rewarded(config: on, context: c) == .refuse(.notEntitledToAds))
        #expect(AdGate.native(placement: "library", config: on, adsEntitled: false) == .refuse(.notEntitledToAds))
    }

    // MARK: Interstitial

    @Test func interstitialAllowedForWarmUser() {
        #expect(AdGate.interstitial(config: on, context: ctx(warmLedger())) == .allow)
    }

    @Test func interstitialNeedsTwoCompletionsEvenIfConfigSaysOne() {
        var config = on
        config.interstitial.minimumCompletionsBetween = 1
        config.interstitial.minimumSecondsBetween = 0
        config.fullScreenCooldownSeconds = 0
        var l = warmLedger()
        l.recordShown(.interstitial, at: t0.addingTimeInterval(-10), calendar: calendar)
        l.recordCompletion()
        #expect(AdGate.interstitial(config: config, context: ctx(l)) == .refuse(.tooFewCompletionsSinceLast))
        l.recordCompletion()
        #expect(AdGate.interstitial(config: config, context: ctx(l)) == .allow)
    }

    @Test func interstitialRespectsSpacingAndCooldown() {
        var l = warmLedger()
        l.recordShown(.interstitial, at: t0.addingTimeInterval(-100), calendar: calendar)
        l.recordFullScreenDismissed(at: t0.addingTimeInterval(-10))
        l.recordCompletion(); l.recordCompletion()
        #expect(AdGate.interstitial(config: on, context: ctx(l)) == .refuse(.fullScreenCooldown))
        #expect(AdGate.interstitial(config: on, context: ctx(l, at: t0.addingTimeInterval(40))) == .refuse(.tooSoonSinceSameFormat))
        #expect(AdGate.interstitial(config: on, context: ctx(l, at: t0.addingTimeInterval(81))) == .allow)
    }

    @Test func interstitialBlockedEarlyInSessionAndForNewUsers() {
        var l = warmLedger()
        l.sessionStartedAt = t0.addingTimeInterval(-10)
        #expect(AdGate.interstitial(config: on, context: ctx(l)) == .refuse(.sessionTooYoung))
        var fresh = AdLedger()
        fresh.recordSessionStart(at: t0.addingTimeInterval(-600))
        fresh.recordCompletion()
        #expect(AdGate.interstitial(config: on, context: ctx(fresh)) == .refuse(.tooFewLifetimeCompletions))
    }

    @Test func dailyCapResetsNextDay() {
        var config = on
        config.interstitial.maxPerDay = 1
        var l = warmLedger()
        l.recordShown(.interstitial, at: t0.addingTimeInterval(-1000), calendar: calendar)
        l.recordFullScreenDismissed(at: t0.addingTimeInterval(-990))
        l.recordCompletion(); l.recordCompletion()
        #expect(AdGate.interstitial(config: config, context: ctx(l)) == .refuse(.dailyCap))
        let tomorrow = t0.addingTimeInterval(86_400)
        l.sessionStartedAt = tomorrow.addingTimeInterval(-600)
        #expect(AdGate.interstitial(config: config, context: ctx(l, at: tomorrow)) == .allow)
    }

    // MARK: App Open

    @Test func appOpenRules() {
        let l = warmLedger()
        #expect(AdGate.appOpen(config: on, context: ctx(l), secondsInBackground: 44) == .refuse(.backgroundTooShort))
        #expect(AdGate.appOpen(config: on, context: ctx(l), secondsInBackground: 45) == .allow)
        var early = AdLedger()
        early.recordSessionStart(at: t0)
        #expect(AdGate.appOpen(config: on, context: ctx(early), secondsInBackground: 999) == .refuse(.earlySession))
    }

    // MARK: Native

    @Test func nativePlacementIsByName() {
        #expect(AdGate.native(placement: "library", config: on, adsEntitled: true) == .allow)
        #expect(AdGate.native(placement: "exportDone", config: on, adsEntitled: true) == .refuse(.placementDisabled))
    }

    @Test func nativeRowsDefaults() {
        let rows = AdGate.nativeRows(itemCount: 100, config: on.native)
        #expect(rows == [5, 15, 25])                       // display rows 6, 17, 28
        #expect(AdGate.nativeRows(itemCount: 5, config: on.native) == [])   // never ends a list
        #expect(AdGate.nativeRows(itemCount: 6, config: on.native) == [5])
    }

    @Test(arguments: [0, 1, 5, 6, 7, 15, 16, 26, 100])
    func nativeChunksAgreeWithRows(count: Int) {
        let items = Array(0..<count)
        let rows = AdGate.nativeRows(itemCount: count, config: on.native)
        let chunks = AdGate.nativeChunks(items: items, config: on.native)
        #expect(chunks.count == rows.count + 1)
        #expect(chunks.flatMap { $0 } == items)
        var boundary = 0
        for (i, row) in rows.enumerated() {
            boundary += chunks[i].count
            #expect(boundary == row)
        }
    }

    // MARK: Config + unit IDs

    @Test func lenientDecodingKeepsDefaultsForBadKeys() {
        let json = #"{"enabled": true, "interstitial": {"maxPerDay": "lots", "minimumSecondsBetween": 240}, "native": 7}"#
        let c = AdsConfig.decode(json)
        #expect(c.enabled)
        #expect(c.interstitial.maxPerDay == 6)
        #expect(c.interstitial.minimumSecondsBetween == 240)
        #expect(c.native == AdsConfig.Native())
        #expect(AdsConfig.decode("not json") == .safeDefault)
    }

    @Test func unitIDTiers() {
        let ids = AdUnitIDs(compiled: [.interstitial: "compiled"])
        let plist: (String) -> String? = { $0 == "GADUnitID_interstitial" ? "plist" : nil }
        #expect(ids.resolve(.interstitial, remote: ["interstitial": "remote"], infoPlist: plist, useTestUnits: false) == "remote")
        #expect(ids.resolve(.interstitial, remote: ["interstitial": "  "], infoPlist: plist, useTestUnits: false) == "plist")
        #expect(ids.resolve(.interstitial, remote: [:], infoPlist: { _ in "" }, useTestUnits: false) == "compiled")
        #expect(ids.resolve(.interstitial, remote: ["interstitial": "remote"], infoPlist: plist, useTestUnits: true)
                == AdUnitIDs.googleTest[.interstitial])
    }
}

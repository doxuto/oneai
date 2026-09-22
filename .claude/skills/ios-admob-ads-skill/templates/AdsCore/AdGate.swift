import Foundation

/// Every timing and placement rule for ads, in one pure function per format.
///
/// The gate never talks to the SDK. Callers ask the gate first and only ask the SDK for a
/// loaded ad after `.allow`, so an ad that isn't ready can never become the reason a rule was
/// skipped. Check order is fixed — master switch, entitlement, format switch, format rules — and
/// each refusal has its own reason so analytics can tell "we said no" from "Google had no fill".
public enum AdGate {

    public enum Decision: Sendable, Equatable {
        case allow
        case refuse(Refusal)

        public var isAllowed: Bool { self == .allow }
    }

    public enum Refusal: String, Sendable, Equatable, Codable {
        case masterSwitchOff
        case notEntitledToAds        // paid / ad-free user
        case formatDisabled
        case placementDisabled
        case dailyCap
        case tooSoonSinceSameFormat
        case fullScreenCooldown
        case tooFewCompletionsSinceLast
        case tooFewLifetimeCompletions
        case sessionTooYoung
        case earlySession            // App Open during the first sessions
        case backgroundTooShort
    }

    /// Everything the gate needs besides config: ledger, entitlement, time.
    public struct Context: Sendable {
        public var ledger: AdLedger
        /// `false` when the user's plan removes ads. Kept apart from `AdsConfig.enabled` on purpose.
        public var adsEntitled: Bool
        public var now: Date
        public var calendar: Calendar

        public init(ledger: AdLedger, adsEntitled: Bool, now: Date, calendar: Calendar = .current) {
            self.ledger = ledger
            self.adsEntitled = adsEntitled
            self.now = now
            self.calendar = calendar
        }
    }

    // MARK: - Full-screen formats

    public static func appOpen(
        config: AdsConfig,
        context: Context,
        secondsInBackground: TimeInterval
    ) -> Decision {
        if let r = common(config: config, context: context) { return .refuse(r) }
        let rules = config.appOpen
        guard rules.enabled else { return .refuse(.formatDisabled) }
        guard context.ledger.sessionCount > rules.skipFirstSessions else { return .refuse(.earlySession) }
        guard secondsInBackground >= rules.minimumBackgroundSeconds else { return .refuse(.backgroundTooShort) }
        if let r = fullScreenCooldown(config: config, context: context) { return .refuse(r) }
        if let r = spacing(.appOpen, seconds: rules.minimumSecondsBetween, context: context) { return .refuse(r) }
        if let r = cap(.appOpen, maxPerDay: rules.maxPerDay, context: context) { return .refuse(r) }
        return .allow
    }

    /// Call from a "done" moment *after* `ledger.recordCompletion()`.
    public static func interstitial(config: AdsConfig, context: Context) -> Decision {
        if let r = common(config: config, context: context) { return .refuse(r) }
        let rules = config.interstitial
        guard rules.enabled else { return .refuse(.formatDisabled) }
        let ledger = context.ledger
        guard ledger.lifetimeCompletions >= rules.minimumLifetimeCompletions else {
            return .refuse(.tooFewLifetimeCompletions)
        }
        // AdMob policy floor: never more than one interstitial per two actions, whatever config says.
        let completionsBetween = max(2, rules.minimumCompletionsBetween)
        if ledger.lastShownAt[.interstitial] != nil, ledger.completionsSinceInterstitial < completionsBetween {
            return .refuse(.tooFewCompletionsSinceLast)
        }
        guard let started = ledger.sessionStartedAt,
              context.now.timeIntervalSince(started) >= rules.minimumSessionSeconds
        else { return .refuse(.sessionTooYoung) }
        if let r = fullScreenCooldown(config: config, context: context) { return .refuse(r) }
        if let r = spacing(.interstitial, seconds: rules.minimumSecondsBetween, context: context) { return .refuse(r) }
        if let r = cap(.interstitial, maxPerDay: rules.maxPerDay, context: context) { return .refuse(r) }
        return .allow
    }

    /// User-initiated. Still capped per day; still subject to master switch and entitlement.
    public static func rewarded(config: AdsConfig, context: Context) -> Decision {
        if let r = common(config: config, context: context) { return .refuse(r) }
        guard config.rewarded.enabled else { return .refuse(.formatDisabled) }
        if let r = cap(.rewarded, maxPerDay: config.rewarded.maxPerDay, context: context) { return .refuse(r) }
        return .allow
    }

    // MARK: - Inline formats

    public static func native(placement: String, config: AdsConfig, adsEntitled: Bool) -> Decision {
        guard config.enabled else { return .refuse(.masterSwitchOff) }
        guard adsEntitled else { return .refuse(.notEntitledToAds) }
        guard config.native.enabled else { return .refuse(.formatDisabled) }
        guard config.native.placements.contains(placement) else { return .refuse(.placementDisabled) }
        return .allow
    }

    public static func banner(placement: String, config: AdsConfig, adsEntitled: Bool) -> Decision {
        guard config.enabled else { return .refuse(.masterSwitchOff) }
        guard adsEntitled else { return .refuse(.notEntitledToAds) }
        guard config.banner.enabled else { return .refuse(.formatDisabled) }
        guard config.banner.placements.contains(placement) else { return .refuse(.placementDisabled) }
        return .allow
    }

    /// Item indices *before which* a native ad is inserted, for lists (`List`, `LazyVStack`,
    /// table views). An ad is only placed with at least one content item after it, so short
    /// lists get none and an ad never ends a list.
    public static func nativeRows(itemCount: Int, config: AdsConfig.Native) -> [Int] {
        let first = max(1, config.firstRow) - 1       // 1-based display row → items before it
        let every = max(1, config.everyRows)
        guard config.maxPerScreen > 0, first >= 0 else { return [] }
        var rows: [Int] = []
        var index = first
        while index < itemCount, rows.count < config.maxPerScreen {
            rows.append(index)
            index += every
        }
        return rows
    }

    /// Items split into chunks with one ad between consecutive chunks, for grids
    /// (`LazyVGrid` cannot insert a full-width row mid-grid). Derived from `nativeRows` so the
    /// two shapes can never disagree on where an ad goes.
    public static func nativeChunks<T>(items: [T], config: AdsConfig.Native) -> [ArraySlice<T>] {
        let cuts = nativeRows(itemCount: items.count, config: config)
        var chunks: [ArraySlice<T>] = []
        var start = items.startIndex
        for cut in cuts {
            chunks.append(items[start..<cut])
            start = cut
        }
        chunks.append(items[start..<items.endIndex])
        return chunks
    }

    // MARK: - Shared checks

    private static func common(config: AdsConfig, context: Context) -> Refusal? {
        guard config.enabled else { return .masterSwitchOff }
        guard context.adsEntitled else { return .notEntitledToAds }
        return nil
    }

    private static func fullScreenCooldown(config: AdsConfig, context: Context) -> Refusal? {
        guard let dismissed = context.ledger.lastFullScreenDismissedAt else { return nil }
        return context.now.timeIntervalSince(dismissed) < config.fullScreenCooldownSeconds ? .fullScreenCooldown : nil
    }

    private static func spacing(_ format: AdFormat, seconds: TimeInterval, context: Context) -> Refusal? {
        guard let last = context.ledger.lastShownAt[format] else { return nil }
        return context.now.timeIntervalSince(last) < seconds ? .tooSoonSinceSameFormat : nil
    }

    private static func cap(_ format: AdFormat, maxPerDay: Int, context: Context) -> Refusal? {
        context.ledger.shownToday(format, on: context.now, calendar: context.calendar) >= maxPerDay ? .dailyCap : nil
    }
}

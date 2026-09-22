import Foundation
import OSLog

/// Outcome of asking the live client to show a full-screen ad.
public enum AdShowResult: Sendable, Equatable {
    /// Presented and dismissed normally.
    case dismissed
    /// Rewarded: the SDK says the user earned the reward. UI hint only — the server credits it.
    case rewardEarnedAndDismissed
    /// Gate allowed it, but no loaded ad was available. Never wait for a load on the trigger.
    case notReady
    case failed(String)
}

/// What the ads layer logs. Nothing here identifies the user.
public enum AdEvent: Sendable, Equatable {
    case refused(AdFormat, placement: String, reason: AdGate.Refusal)
    case filled(AdFormat, placement: String)
    case noFill(AdFormat, placement: String, error: String)
    case notReady(AdFormat, placement: String)
    case shown(AdFormat, placement: String)
    case dismissed(AdFormat, placement: String)
    case rewardEarned(placement: String)
}

/// Revenue for one impression, from the SDK's `paidEventHandler`.
public struct AdImpression: Sendable, Equatable {
    public var format: AdFormat
    public var placement: String
    public var valueMicros: Int64
    public var currencyCode: String
    /// Precision reported by the SDK: "estimated", "publisherProvided", "precise", "unknown".
    public var precision: String
    /// Ad source that filled (e.g. "AdMob Network"), when the SDK reports it.
    public var adSource: String?

    public init(format: AdFormat, placement: String, valueMicros: Int64, currencyCode: String,
                precision: String, adSource: String?) {
        self.format = format
        self.placement = placement
        self.valueMicros = valueMicros
        self.currencyCode = currencyCode
        self.precision = precision
        self.adSource = adSource
    }
}

/// Sink for ad analytics. Live default: unified log only (see references/analytics.md).
public struct AdAnalytics: Sendable {
    public var event: @Sendable (AdEvent) -> Void
    public var impression: @Sendable (AdImpression) -> Void

    public init(event: @escaping @Sendable (AdEvent) -> Void,
                impression: @escaping @Sendable (AdImpression) -> Void) {
        self.event = event
        self.impression = impression
    }

    public static let noop = AdAnalytics(event: { _ in }, impression: { _ in })

    /// Unified log only. Pointing this at an analytics backend is a privacy-label decision,
    /// not a code decision — keep it the single place that changes.
    public static let log: AdAnalytics = {
        let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ads", category: "ads")
        return AdAnalytics(
            event: { logger.info("ad event: \(String(describing: $0), privacy: .public)") },
            impression: { i in
                logger.info("ad impression: \(i.format.rawValue, privacy: .public) \(i.placement, privacy: .public) \(i.valueMicros) \(i.currencyCode, privacy: .public) \(i.precision, privacy: .public)")
            })
    }()
}

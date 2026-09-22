import Foundation

public enum AdFormat: String, Sendable, Codable, CodingKeyRepresentable, CaseIterable {
    case appOpen, interstitial, rewarded, rewardedInterstitial, native, banner

    public var isFullScreen: Bool {
        switch self {
        case .appOpen, .interstitial, .rewarded, .rewardedInterstitial: true
        case .native, .banner: false
        }
    }
}

/// Persisted counters the gate reads. Pure value type: store it as JSON wherever the app keeps
/// small preferences (UserDefaults is fine — nothing here identifies the user).
///
/// All mutations take the time and calendar explicitly so they stay testable.
public struct AdLedger: Sendable, Equatable, Codable {
    public var sessionCount = 0
    public var sessionStartedAt: Date?
    public var lifetimeCompletions = 0
    public var completionsSinceInterstitial = 0
    public var lastShownAt: [AdFormat: Date] = [:]
    public var lastFullScreenDismissedAt: Date?
    /// Local calendar day the per-day counters belong to, "yyyy-MM-dd".
    public var dayKey = ""
    public var shownToday: [AdFormat: Int] = [:]

    public init() {}

    // MARK: Day handling

    public static func dayKey(for date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// The ledger as seen on `date`: per-day counters are empty if the day changed.
    public func normalized(for date: Date, calendar: Calendar) -> AdLedger {
        let key = Self.dayKey(for: date, calendar: calendar)
        guard key != dayKey else { return self }
        var copy = self
        copy.dayKey = key
        copy.shownToday = [:]
        return copy
    }

    public func shownToday(_ format: AdFormat, on date: Date, calendar: Calendar) -> Int {
        normalized(for: date, calendar: calendar).shownToday[format, default: 0]
    }

    // MARK: Mutations

    public mutating func recordSessionStart(at date: Date) {
        sessionCount += 1
        sessionStartedAt = date
    }

    /// Call on every "done" moment, whether or not an ad is shown — spacing counts actions.
    public mutating func recordCompletion() {
        lifetimeCompletions += 1
        completionsSinceInterstitial += 1
    }

    /// Call when the SDK reports the ad was actually presented / rendered.
    public mutating func recordShown(_ format: AdFormat, at date: Date, calendar: Calendar) {
        self = normalized(for: date, calendar: calendar)
        shownToday[format, default: 0] += 1
        lastShownAt[format] = date
        if format == .interstitial { completionsSinceInterstitial = 0 }
    }

    public mutating func recordFullScreenDismissed(at date: Date) {
        lastFullScreenDismissedAt = date
    }
}

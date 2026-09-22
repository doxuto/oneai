import Foundation

/// Remote-tunable ad configuration (`ads_config` JSON).
///
/// Decoding is lenient on purpose: any missing or mistyped key falls back to the safe default
/// for that key only, so a half-edited Remote Config block can never make ads more aggressive
/// or break unrelated keys. `AdsConfig.safeDefault` is what a build that never reached Remote
/// Config runs with: ads off.
public struct AdsConfig: Sendable, Equatable, Codable {
    public var enabled: Bool
    /// No full-screen ad of any format within this many seconds of the last full-screen dismissal.
    public var fullScreenCooldownSeconds: Double
    public var appOpen: AppOpen
    public var interstitial: Interstitial
    public var native: Native
    public var banner: Banner
    public var rewarded: Rewarded
    /// Unit ID overrides keyed by `AdFormat.rawValue`. Unknown keys are kept, not rejected.
    public var unitIDs: [String: String]

    public static let safeDefault = AdsConfig(
        enabled: false,
        fullScreenCooldownSeconds: 30,
        appOpen: .init(),
        interstitial: .init(),
        native: .init(),
        banner: .init(),
        rewarded: .init(),
        unitIDs: [:]
    )

    public init(
        enabled: Bool,
        fullScreenCooldownSeconds: Double,
        appOpen: AppOpen,
        interstitial: Interstitial,
        native: Native,
        banner: Banner,
        rewarded: Rewarded,
        unitIDs: [String: String]
    ) {
        self.enabled = enabled
        self.fullScreenCooldownSeconds = fullScreenCooldownSeconds
        self.appOpen = appOpen
        self.interstitial = interstitial
        self.native = native
        self.banner = banner
        self.rewarded = rewarded
        self.unitIDs = unitIDs
    }

    /// Decodes a Remote Config JSON string; any failure yields `safeDefault`.
    public static func decode(_ json: String?) -> AdsConfig {
        guard let data = json?.data(using: .utf8), !data.isEmpty,
              let config = try? JSONDecoder().decode(AdsConfig.self, from: data)
        else { return .safeDefault }
        return config
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AdsConfig.safeDefault
        enabled = c.lenient(Bool.self, .enabled) ?? d.enabled
        fullScreenCooldownSeconds = c.lenient(Double.self, .fullScreenCooldownSeconds) ?? d.fullScreenCooldownSeconds
        appOpen = c.lenient(AppOpen.self, .appOpen) ?? d.appOpen
        interstitial = c.lenient(Interstitial.self, .interstitial) ?? d.interstitial
        native = c.lenient(Native.self, .native) ?? d.native
        banner = c.lenient(Banner.self, .banner) ?? d.banner
        rewarded = c.lenient(Rewarded.self, .rewarded) ?? d.rewarded
        unitIDs = c.lenient([String: String].self, .unitIDs) ?? d.unitIDs
    }

    // MARK: - Formats

    public struct AppOpen: Sendable, Equatable, Codable {
        public var enabled = true
        public var minimumBackgroundSeconds: Double = 45
        public var minimumSecondsBetween: Double = 300
        public var maxPerDay = 4
        public var skipFirstSessions = 3

        public init() {}

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Self()
            enabled = c.lenient(Bool.self, .enabled) ?? d.enabled
            minimumBackgroundSeconds = c.lenient(Double.self, .minimumBackgroundSeconds) ?? d.minimumBackgroundSeconds
            minimumSecondsBetween = c.lenient(Double.self, .minimumSecondsBetween) ?? d.minimumSecondsBetween
            maxPerDay = c.lenient(Int.self, .maxPerDay) ?? d.maxPerDay
            skipFirstSessions = c.lenient(Int.self, .skipFirstSessions) ?? d.skipFirstSessions
        }
    }

    public struct Interstitial: Sendable, Equatable, Codable {
        public var enabled = true
        public var minimumSecondsBetween: Double = 180
        /// AdMob allows at most one interstitial per two user actions. Clamped to >= 2 by `AdGate`.
        public var minimumCompletionsBetween = 2
        public var maxPerDay = 6
        public var minimumSessionSeconds: Double = 60
        public var minimumLifetimeCompletions = 3

        public init() {}

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Self()
            enabled = c.lenient(Bool.self, .enabled) ?? d.enabled
            minimumSecondsBetween = c.lenient(Double.self, .minimumSecondsBetween) ?? d.minimumSecondsBetween
            minimumCompletionsBetween = c.lenient(Int.self, .minimumCompletionsBetween) ?? d.minimumCompletionsBetween
            maxPerDay = c.lenient(Int.self, .maxPerDay) ?? d.maxPerDay
            minimumSessionSeconds = c.lenient(Double.self, .minimumSessionSeconds) ?? d.minimumSessionSeconds
            minimumLifetimeCompletions = c.lenient(Int.self, .minimumLifetimeCompletions) ?? d.minimumLifetimeCompletions
        }
    }

    public struct Native: Sendable, Equatable, Codable {
        public var enabled = true
        /// Placement names allowed to render. Names, not indexes, so one can be switched off remotely.
        public var placements: [String] = []
        /// 1-based display row of the first ad (6 = after five content rows).
        public var firstRow = 6
        public var everyRows = 10
        public var maxPerScreen = 3

        public init() {}

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Self()
            enabled = c.lenient(Bool.self, .enabled) ?? d.enabled
            placements = c.lenient([String].self, .placements) ?? d.placements
            firstRow = c.lenient(Int.self, .firstRow) ?? d.firstRow
            everyRows = c.lenient(Int.self, .everyRows) ?? d.everyRows
            maxPerScreen = c.lenient(Int.self, .maxPerScreen) ?? d.maxPerScreen
        }
    }

    public struct Banner: Sendable, Equatable, Codable {
        public var enabled = false
        public var placements: [String] = []

        public init() {}

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Self()
            enabled = c.lenient(Bool.self, .enabled) ?? d.enabled
            placements = c.lenient([String].self, .placements) ?? d.placements
        }
    }

    public struct Rewarded: Sendable, Equatable, Codable {
        public var enabled = true
        public var maxPerDay = 3
        /// For UI copy only. The server decides and clamps the real grant.
        public var grantAmount = 5

        public init() {}

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Self()
            enabled = c.lenient(Bool.self, .enabled) ?? d.enabled
            maxPerDay = c.lenient(Int.self, .maxPerDay) ?? d.maxPerDay
            grantAmount = c.lenient(Int.self, .grantAmount) ?? d.grantAmount
        }
    }
}

extension KeyedDecodingContainer {
    /// Returns nil for a missing key *or* a value of the wrong type, instead of throwing.
    fileprivate func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}

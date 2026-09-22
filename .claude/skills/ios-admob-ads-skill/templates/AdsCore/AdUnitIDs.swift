import Foundation

/// Ad unit ID resolution: Remote Config `unitIDs` → Info.plist `GADUnitID_<format>` → compiled
/// constant. Each tier is skipped when empty, so a half-filled override block can never leave a
/// format without an ID.
///
/// Debug builds ignore all three and always return Google's official test units: impressions
/// from development devices are invalid traffic, and invalid traffic closes AdMob accounts.
public struct AdUnitIDs: Sendable, Equatable {
    /// Production IDs compiled into the app — the last-resort tier. Fill per app.
    public var compiled: [AdFormat: String]

    public init(compiled: [AdFormat: String]) {
        self.compiled = compiled
    }

    /// Google's official iOS test ad units.
    public static let googleTest: [AdFormat: String] = [
        .appOpen: "ca-app-pub-3940256099942544/5575463023",
        .interstitial: "ca-app-pub-3940256099942544/4411468910",
        .rewarded: "ca-app-pub-3940256099942544/1712485313",
        .rewardedInterstitial: "ca-app-pub-3940256099942544/6978759866",
        .native: "ca-app-pub-3940256099942544/3986624511",
        .banner: "ca-app-pub-3940256099942544/2435281174",
    ]
    public static let googleTestAppID = "ca-app-pub-3940256099942544~1458002511"

    public static func infoPlistKey(for format: AdFormat) -> String { "GADUnitID_\(format.rawValue)" }

    /// - Parameters:
    ///   - remote: `AdsConfig.unitIDs`.
    ///   - infoPlist: lookup into the main bundle's Info.plist (injected for tests).
    ///   - useTestUnits: pass `isDebugBuild` in production code; tests pass `false` to exercise tiers.
    public func resolve(
        _ format: AdFormat,
        remote: [String: String],
        infoPlist: (String) -> String?,
        useTestUnits: Bool = AdUnitIDs.isDebugBuild
    ) -> String? {
        if useTestUnits { return Self.googleTest[format] }
        let candidates: [String?] = [
            remote[format.rawValue],
            infoPlist(Self.infoPlistKey(for: format)),
            compiled[format],
        ]
        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    public static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

extension Bundle {
    /// Convenience for `AdUnitIDs.resolve(infoPlist:)`.
    public func adInfoString(_ key: String) -> String? {
        object(forInfoDictionaryKey: key) as? String
    }
}

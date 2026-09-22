// Live AdMob client. App target only — features never import GoogleMobileAds.
//
// Written against Google Mobile Ads SDK 12.x and UMP 3.x Swift names. On SDK 11 or earlier,
// prefix types with GAD/UMP (GADInterstitialAd, UMPConsentInformation, …). Verify against the
// installed version before adapting; don't mix naming generations.
//
// This file does NOT decide whether to show an ad: callers ask AdGate first. It only loads,
// keeps one preloaded ad per full-screen format, presents on request, and reports what happened.

import Foundation
import GoogleMobileAds
import OSLog
import UIKit
import UserMessagingPlatform
// import AdsCore   // the module holding AdsConfig / AdGate / AdUnitIDs / AdEvent

@MainActor
public final class AdsLiveController: NSObject {

    public private(set) var config: AdsConfig = .safeDefault
    private let unitIDs: AdUnitIDs
    private let analytics: AdAnalytics
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ads", category: "ads")

    private var started = false
    private var slots: [AdFormat: Slot] = [:]
    private var pending: CheckedContinuation<AdShowResult, Never>?
    private var pendingFormat: AdFormat?
    private var pendingPlacement = ""
    private var rewardEarned = false

    /// Loaded ads older than this are discarded (App Open expires at 4 h; others ~1 h is safe).
    private let maxAge: [AdFormat: TimeInterval] = [.appOpen: 4 * 3600, .interstitial: 3300, .rewarded: 3300]

    private struct Slot {
        var ad: (any FullScreenPresentingAd)?
        var loadedAt: Date?
        var loading = false
        var failures = 0
    }

    public init(unitIDs: AdUnitIDs, analytics: AdAnalytics) {
        self.unitIDs = unitIDs
        self.analytics = analytics
    }

    // MARK: - Lifecycle

    /// Call whenever Remote Config activates. Turning ads off drops loaded ads; the SDK stays
    /// initialized if it already was (it can't be un-started), but nothing else is requested.
    public func apply(config: AdsConfig) async {
        self.config = config
        if config.enabled {
            await start()
        } else {
            slots.removeAll()
        }
    }

    /// Consent first, then SDK start, then preload. Does nothing while the master switch is off:
    /// ads disabled means no SDK start and no consent prompt.
    public func start() async {
        guard config.enabled, !started else { return }
        await gatherConsent()
        guard ConsentInformation.shared.canRequestAds else {
            log.info("ads: consent does not allow requests yet")
            return
        }
        started = true
        _ = await MobileAds.shared.start()
        preloadAll()
    }

    private func gatherConsent() async {
        let params = RequestParameters()
        #if DEBUG
        // To test the EEA form: params.debugSettings = { let d = DebugSettings(); d.geography = .EEA; d.testDeviceIdentifiers = ["<hash>"]; return d }()
        #endif
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: params)
            if ConsentInformation.shared.canRequestAds == false, let root = Self.topViewController() {
                try await ConsentForm.loadAndPresentIfRequired(from: root)
            }
        } catch {
            // Consent errors must not block the app. canRequestAds decides what happens next.
            log.error("ads: consent error \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Settings should show a "Privacy options" row when this is true.
    public var privacyOptionsRequired: Bool {
        ConsentInformation.shared.privacyOptionsRequirementStatus == .required
    }

    public func presentPrivacyOptions() async {
        guard let root = Self.topViewController() else { return }
        try? await ConsentForm.presentPrivacyOptionsForm(from: root)
    }

    /// Call when the user's entitlement becomes ad-free: drop everything loaded.
    public func clearForAdFreeUser() {
        slots.removeAll()
    }

    // MARK: - Loading

    private func preloadAll() {
        if config.appOpen.enabled { load(.appOpen) }
        if config.interstitial.enabled { load(.interstitial) }
        if config.rewarded.enabled { load(.rewarded) }
    }

    private func makeRequest() -> Request {
        let request = Request()
        // Non-personalized only (no ATT). Remove only as part of the full tracking package.
        let extras = Extras()
        extras.additionalParameters = ["npa": "1"]
        request.register(extras)
        return request
    }

    private func load(_ format: AdFormat) {
        guard started, config.enabled, slots[format]?.loading != true else { return }
        guard let id = unitIDs.resolve(format, remote: config.unitIDs, infoPlist: Bundle.main.adInfoString) else {
            log.error("ads: no unit id for \(format.rawValue, privacy: .public)")
            return
        }
        slots[format, default: Slot()].loading = true
        Task { @MainActor in
            do {
                let ad: any FullScreenPresentingAd
                switch format {
                case .appOpen:
                    let a = try await AppOpenAd.load(with: id, request: makeRequest())
                    a.paidEventHandler = { [weak self] value in MainActor.assumeIsolated { self?.reportPaid(value, format: format) } }
                    ad = a
                case .interstitial:
                    let a = try await InterstitialAd.load(with: id, request: makeRequest())
                    a.paidEventHandler = { [weak self] value in MainActor.assumeIsolated { self?.reportPaid(value, format: format) } }
                    ad = a
                case .rewarded:
                    let a = try await RewardedAd.load(with: id, request: makeRequest())
                    a.paidEventHandler = { [weak self] value in MainActor.assumeIsolated { self?.reportPaid(value, format: format) } }
                    ad = a
                default:
                    return
                }
                ad.fullScreenContentDelegate = self
                slots[format] = Slot(ad: ad, loadedAt: Date(), loading: false, failures: 0)
                analytics.event(.filled(format, placement: format.rawValue))
            } catch {
                var slot = slots[format] ?? Slot()
                slot.loading = false
                slot.failures += 1
                slots[format] = slot
                analytics.event(.noFill(format, placement: format.rawValue, error: error.localizedDescription))
                // Exponential backoff: 30 s, 60 s, 120 s … capped at 10 min. Don't hammer on no-fill.
                let delay = min(600, 30 * pow(2, Double(slot.failures - 1)))
                try? await Task.sleep(for: .seconds(delay))
                load(format)
            }
        }
    }

    private func reportPaid(_ value: AdValue, format: AdFormat) {
        let micros = value.value.multiplying(byPowerOf10: 6).int64Value
        let precision: String = switch value.precision {
        case .estimated: "estimated"
        case .publisherProvided: "publisherProvided"
        case .precise: "precise"
        default: "unknown"
        }
        analytics.impression(AdImpression(
            format: format,
            placement: pendingFormat == format ? pendingPlacement : format.rawValue,
            valueMicros: micros,
            currencyCode: value.currencyCode,
            precision: precision,
            adSource: nil))
    }

    private func freshAd(_ format: AdFormat) -> (any FullScreenPresentingAd)? {
        guard let slot = slots[format], let ad = slot.ad, let loadedAt = slot.loadedAt else { return nil }
        if Date().timeIntervalSince(loadedAt) > maxAge[format, default: 3300] {
            slots[format] = nil
            load(format)
            return nil
        }
        return ad
    }

    // MARK: - Presenting (call only after AdGate returned .allow)

    public func showAppOpen() async -> AdShowResult {
        await present(.appOpen, placement: "appOpen") { ad, root in
            (ad as? AppOpenAd)?.present(from: root)
        }
    }

    public func showInterstitial(placement: String) async -> AdShowResult {
        await present(.interstitial, placement: placement) { ad, root in
            (ad as? InterstitialAd)?.present(from: root)
        }
    }

    /// `userID` is your own opaque auth uid; Google forwards it to the SSV callback.
    /// The reward is credited by the server, never here.
    public func showRewarded(placement: String, userID: String, customData: String? = nil) async -> AdShowResult {
        await present(.rewarded, placement: placement) { [weak self] ad, root in
            guard let rewarded = ad as? RewardedAd else { return }
            let options = ServerSideVerificationOptions()
            options.userIdentifier = userID
            options.customRewardString = customData
            rewarded.serverSideVerificationOptions = options   // set on the ad about to be shown
            rewarded.present(from: root) {
                MainActor.assumeIsolated {
                    self?.rewardEarned = true
                    self?.analytics.event(.rewardEarned(placement: placement))
                }
            }
        }
    }

    private func present(
        _ format: AdFormat,
        placement: String,
        _ show: @escaping (any FullScreenPresentingAd, UIViewController) -> Void
    ) async -> AdShowResult {
        guard pending == nil else { return .notReady }   // one full-screen ad at a time
        guard let ad = freshAd(format), let root = Self.topViewController() else {
            analytics.event(.notReady(format, placement: placement))
            load(format)
            return .notReady
        }
        slots[format] = nil
        pendingFormat = format
        pendingPlacement = placement
        rewardEarned = false
        return await withCheckedContinuation { continuation in
            pending = continuation
            show(ad, root)
        }
    }

    private func finish(_ result: AdShowResult) {
        let format = pendingFormat
        pending?.resume(returning: result)
        pending = nil
        pendingFormat = nil
        if let format { load(format) }
    }

    // MARK: - Helpers

    static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}

// MARK: - FullScreenContentDelegate

extension AdsLiveController: @preconcurrency FullScreenContentDelegate {
    public func adWillPresentFullScreenContent(_ ad: any FullScreenPresentingAd) {
        guard let format = pendingFormat else { return }
        // The caller records `ledger.recordShown` when show… returns; this is for logs only.
        analytics.event(.shown(format, placement: pendingPlacement))
    }

    public func adDidDismissFullScreenContent(_ ad: any FullScreenPresentingAd) {
        if let format = pendingFormat {
            analytics.event(.dismissed(format, placement: pendingPlacement))
        }
        finish(rewardEarned ? .rewardEarnedAndDismissed : .dismissed)
    }

    public func ad(_ ad: any FullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: any Error) {
        finish(.failed(error.localizedDescription))
    }
}

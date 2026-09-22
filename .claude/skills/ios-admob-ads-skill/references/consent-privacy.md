# Consent, tracking and privacy

## Default stance: non-personalized, no ATT

- Don't request ATT. Serve non-personalized ads only (`npa=1` on every request).
- The SDK still serves ads without IDFA; eCPM is lower, but the App Privacy label has no
  "Data Used to Track You" section, which is a real selling point for apps handling private data.
- `NSPrivacyTracking = false` in the app's privacy manifest.
- If the project later wants personalized ads, it's a **package change**, not a flag: request ATT
  (with `NSUserTrackingUsageDescription`) before loading ads, set `NSPrivacyTracking = true`, list
  `NSPrivacyTrackingDomains`, update the nutrition label to Tracking = Yes, drop `npa`. Doing
  these piecemeal is how the label says one thing and the app does another.

## UMP (Google User Messaging Platform)

Required for EEA/UK/CH users (GDPR) and some US states. It affects all users once integrated.

Order at launch, **only if `ads.enabled` is true**:

1. `ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())`
2. `ConsentForm.loadAndPresentIfRequired(from: rootVC)`
3. If `ConsentInformation.shared.canRequestAds` → `MobileAds.shared.start()` then preload.
4. Also check `canRequestAds` right after step 1 (returning users) so ads aren't delayed by the form.

Add a "Privacy options" row in Settings when
`ConsentInformation.shared.privacyOptionsRequirementStatus == .required`, calling
`ConsentForm.presentPrivacyOptionsForm(from:)`.

Debug: `RequestParameters.debugSettings` with `geography = .EEA` and your test device hash to see
the form; `ConsentInformation.shared.reset()` to re-test. Never ship debug settings.

Configure the GDPR message in the AdMob console (Privacy & messaging) — the SDK shows nothing
without a published message.

## Info.plist

- `GADApplicationIdentifier` — the AdMob App ID (`ca-app-pub-…~…`). Debug may use Google's test
  app ID `ca-app-pub-3940256099942544~1458002511` via a build setting.
- `SKAdNetworkItems` — Google's list (copy the current one from Google's docs; it changes).
- `GADUnitID_<format>` keys (optional second tier of unit ID resolution).
- No `NSUserTrackingUsageDescription` under the default stance.

## App Store Connect

Declare by **binary capability**, not by Remote Config state:

- Tick **Third-Party Advertising** (and In-App Purchases if any).
- App Privacy data types collected by the GMA SDK: Device ID, Advertising Data, Product
  Interaction, Crash Data, Performance Data, Coarse Location (from IP) — **Linked: No,
  Tracking: No** under the default stance; purpose: Third-Party Advertising (+ Analytics if used).
- Remove any "no ads" / "completely free" claim from the description.
- GMA SDK ≥ 11.2 ships its own privacy manifest; mediation adapters must too.

## Data hygiene

- Never put user content in `Request.keywords`, `contentURL`, or custom targeting.
- The only identifier sent is the auth uid in SSV `userIdentifier`, and only for rewarded — it's
  your own opaque ID, not an email or phone.

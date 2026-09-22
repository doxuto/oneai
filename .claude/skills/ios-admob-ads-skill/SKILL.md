---
name: ios-admob-ads
description: Reusable, policy-safe Google AdMob integration for iOS apps (Swift, SwiftUI or UIKit, TCA-friendly) — app open, interstitial, rewarded, rewarded interstitial, native and banner ads behind one pure frequency gate, remote-config-driven thresholds and ad unit IDs, UMP consent with no ATT, native ads rendered through NativeAdView, and rewarded ads credited only by server-side verification (Firebase Functions). Use this skill whenever the user wants to add, port, audit, tune or debug ads in an iOS app — mentions AdMob, Google Mobile Ads, GMA SDK, ad units, interstitial, app open, rewarded, native ads, banner, UMP, consent, SSV, eCPM, "where should ads go", ad frequency caps, or a suspended/limited AdMob account — even if they don't say "skill".
---

# iOS AdMob Ads

A complete, reusable way to put AdMob into an iOS app without getting the AdMob account
suspended and without making people delete the app. It was extracted from a shipped
implementation (SnapTool, ported from MeeGenius's `ComposableGoogleMobileAds`), then made
app-agnostic.

## The one idea behind everything

Two failures are permanent and one is not:

1. **Account suspension for *how* ads are placed** (timing, placement, invalid traffic).
   Google suspends for implementation, not content.
2. **Uninstalls and one-star reviews.** They don't come back.
3. Low fill / low revenue — fixable next week by editing Remote Config.

So every default in this skill sits on the cautious side, every threshold is remote-tunable,
and the code is structured so a rule can't be skipped by accident. When a trade-off between
revenue and (1) or (2) comes up, choose (1)/(2) and say so.

## Hard rules (never break, never "just for now")

1. **Debug builds never request real ad units.** Under `#if DEBUG` every format resolves to
   Google's official test unit, ignoring Remote Config and Info.plist. Impressions from dev
   devices are invalid traffic, and invalid traffic closes accounts.
2. **All timing rules live in one pure function, `AdGate`**, which never touches the SDK. The
   SDK is asked for an ad only *after* the gate says yes — so "ad not loaded yet" can never
   become the reason a rule was skipped. See `references/architecture.md`.
3. **Two separate switches, checked in this order:** the global `ads.enabled` (do we run ads
   at all?) and the user's entitlement `adsEnabled` (did this person pay to not see ads?).
   Never merge them — merging is how a paying subscriber sees an ad, and that's the ad that
   generates refunds.
4. **Master switch off means the SDK is not started and consent is not requested** — not "runs
   but stays quiet". Ship new apps with `ads.enabled = false` and turn it on remotely, format by
   format, after checking on a real device.
5. **Interstitials only between content pages**: never at launch, never at exit, never after
   every action (max 1 per 2 completions), never right after another full-screen ad. Launch
   ads use the App Open format.
6. **No ads on "work" screens** (camera, editor, reader, player, form, AI result — whatever the
   app's core job is). Ads go on "browse" screens and "done" moments only.
7. **Rewarded: the client never credits the reward.** Google calls your server (SSV); the
   server verifies the signature, consumes `transaction_id` once, then grants. The SDK's
   `userDidEarnReward` callback only shows a message. See `references/rewarded-ssv.md`.
8. **Native ads are drawn inside the SDK's `NativeAdView`** with registered asset views. A
   SwiftUI card built from `headline`/`body` strings earns nothing and violates policy.
9. **Never pass user content or PII to ad requests** (document text, file names, tags, search
   terms, emails). Contextual targeting parameters stay empty.
10. **Privacy labels describe the binary, not the switch.** If the SDK is linked, App Store
    Connect must declare Third-Party Advertising and the AdMob data types, even while
    `ads.enabled = false`.

## Workflow: adding ads to a new app

Work through these in order. Each step points to the reference with the detail. Read a
reference when you reach its step, not all up front.

1. **Decide placements first, code second.** Classify every screen as *work* or *browse*, list
   the "done" moments, and fill the placement table. → `references/placement-playbook.md`
2. **Confirm product decisions with the user** before writing code: which formats, whether
   there's a paid tier (entitlement source), whether rewarded grants something server-side,
   whether EU users exist (UMP), ATT yes/no (default: no, non-personalized only). Don't guess
   these — they change App Store metadata.
3. **Add the core module** (pure Swift, no SDK import): copy `templates/AdsCore/*.swift` into
   the app's core/shared package and `templates/Tests/AdGateTests.swift` into its tests. Rename
   placement cases to the app's own. Run the tests. → `references/architecture.md`
4. **Add Remote Config defaults** from `templates/ads_config.defaults.json` (master switch
   **false**). → `references/config-schema.md`
5. **Add the live module** (imports GoogleMobileAds + UMP): adapt
   `templates/AdsLive/AdsLiveClient.swift`. Check the installed SDK's API names first — the
   template targets GMA SDK 12.x Swift names. → `references/formats.md`
6. **Consent + privacy**: UMP flow, `npa=1`, Info.plist keys, privacy manifest, nutrition label.
   → `references/consent-privacy.md`
7. **Native ads** (if used): the DesignSystem-slot / app-target-host split and the ad pool.
   There is no native UI template yet — build `NativeAdCardView` (a `UIViewRepresentable` around
   `NativeAdView`) and `NativeAdPool` from the rules there. → `references/native-ads.md`
8. **Rewarded** (if used): client side + `templates/server/adReward.ts`.
   → `references/rewarded-ssv.md`
9. **Measurement**: impression revenue + refusal reasons. → `references/analytics.md`
10. **Pre-launch checklist**. → `references/launch-checklist.md`

For an **audit** of an existing integration, go straight to `references/launch-checklist.md`
and `references/policy-rules.md` and report violations by severity (account risk first).

For **tuning** ("revenue is low", "users complain"), read `references/config-schema.md` and
`references/analytics.md`: first separate *refused by our gate* from *no fill* before touching
any threshold.

## Adapting to the host project

- **Architecture**: the core is plain Swift structs + a pure enum, so it works with TCA
  (any version — expose it through a `@DependencyClient`/`DependencyKey`), MVVM or plain UIKit.
  Match the project's existing dependency style rather than introducing a new one.
- **Swift 6 / strict concurrency**: templates are `Sendable` and main-actor-isolated where they
  touch UIKit. Keep it that way.
- **Existing conventions win** over the templates for naming, folder layout, comments language
  and test framework. The rules above do not bend.
- **Remote config source**: Firebase Remote Config is assumed; any JSON source works because
  `AdsConfig` decodes leniently (missing keys fall back to safe defaults, one bad domain never
  breaks another).

## Files in this skill

| Path | What |
|---|---|
| `references/policy-rules.md` | AdMob + Apple rules with the reason each exists |
| `references/placement-playbook.md` | Work vs browse screens, placement table, per-format defaults |
| `references/architecture.md` | Module split, AdGate contract, ledger, dependency client |
| `references/config-schema.md` | `ads_config` keys, defaults, unit ID resolution order |
| `references/formats.md` | Per-format implementation notes and pitfalls |
| `references/native-ads.md` | NativeAdView, pool keyed by (placement, slot), list/grid insertion |
| `references/rewarded-ssv.md` | End-to-end rewarded flow with server-side verification |
| `references/consent-privacy.md` | UMP, no-ATT, npa, privacy manifest, nutrition label |
| `references/analytics.md` | Impression revenue + refusal events |
| `references/launch-checklist.md` | Pre-launch / audit checklist |
| `templates/AdsCore/` | `AdsConfig`, `AdLedger`, `AdGate`, `AdUnitIDs`, `AdEvent` (pure Swift, no SDK) |
| `templates/Tests/AdGateTests.swift` | Swift Testing suite for the gate |
| `templates/AdsLive/AdsLiveClient.swift` | GMA SDK + UMP live client |
| `templates/ads_config.defaults.json` | Remote Config defaults (safe side) |
| `templates/server/adReward.ts` | Firebase Function verifying SSV callbacks (typechecked) |
| `templates/server/adReward.test.mts` | Signature tests incl. `%2F` and tampering (`node --experimental-strip-types`) |

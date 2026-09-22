# Policy rules — and why each exists

Tags: **[AdMob]** Google policy (violations risk suspension), **[Apple]** App Review /
guidelines, **[Ours]** a stricter house rule that protects retention.

## Timing (AdMob)

| Rule | Where it's enforced |
|---|---|
| No interstitial at app launch or app exit. Use App Open for launch. | Placement table; `AdGate.interstitial` is only called from "done" moments |
| No interstitial after every action (tap, swipe, back). Max 1 per 2 completions. | `interstitial.minimumCompletionsBetween` (default 2, never below 2) |
| No interstitial right after an interstitial the user just closed. | `fullScreenCooldownSeconds` + `interstitial.minimumSecondsBetween` |
| Don't place ads where they block main content or navigation. | Work-screen ban (placement playbook) |
| Preload, so ads don't pop in late over freshly shown content. | Live client preloads after each show; never load-then-show on the trigger |

Three of these five are about *timing*, and timing logic scattered across features is how a rule
gets skipped. That's why they all live in `AdGate`.

## Traffic (AdMob) — the fastest way to lose the account

- **Never load real units in Debug.** `AdUnitIDs.resolve` returns Google test IDs under
  `#if DEBUG`. Also register test devices for TestFlight/Release testing on your own phone
  (`MobileAds.shared.requestConfiguration.testDeviceIdentifiers`).
- **Never click your own live ads.** Tell QA and the team.
- **Never incentivize clicks** ("tap the ad to continue"). Rewarded rewards *watching*, not clicking.
- **Request/impression ratio matters.** Requesting ads you never show (e.g., re-requesting a
  native ad every time a cell is reused) looks like a broken or abusive integration. See the
  native pool rules.

## Content and data (AdMob)

- Don't pass anything Google could recognize as PII. Don't put user content (document text,
  file names, tags, search terms) into targeting/keywords/content URL.
- No personalization on sensitive categories. Simplest compliant stance: non-personalized
  ads only (`npa=1`) and no ATT.
- Native ads must be clearly labeled ("Ad"/"Quảng cáo") and must not mimic app content rows.

## Apple

- If the SDK is in the binary, declare Third-Party Advertising + data types in App Privacy,
  even if ads are remotely disabled. **[Apple]**
- Don't claim "no ads" / "completely free" in the App Store description once the SDK ships. **[Apple]**
- ATT prompt only if you actually track; if you request it, `NSUserTrackingUsageDescription`
  must exist and ads must wait for the answer. **[Apple]**
- Ads must not appear in contexts reviewers consider child-directed unless the app is set up for
  that (Made for Kids requires certified networks + no personalization). **[Apple][AdMob]**

## Retention (Ours)

- App Open only after ≥45 s in background, and not during the first sessions. Below that,
  switching away to copy a phone number gets punished with a full-screen ad — that alone makes
  people say "this app is full of ads".
- Banner off by default. It's the most seen and most hated format, and it steals space from the
  most important button. Keep it in config only to A/B against native.
- Rewarded is the only format the user chooses, and the only one that gives something back.
  Invest there first.

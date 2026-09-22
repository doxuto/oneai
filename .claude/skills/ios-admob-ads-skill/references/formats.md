# Formats — implementation notes

API names below are **Google Mobile Ads SDK 12.x Swift names** (`MobileAds`, `InterstitialAd`,
`AppOpenAd`, `RewardedAd`, `Request`, `FullScreenContentDelegate`). SDK 11 and earlier use the
`GAD`-prefixed names (`GADMobileAds`, `GADInterstitialAd`, …). Check `Package.resolved` /
`Podfile.lock` first and adapt the template; don't mix.

## Common to all full-screen formats

- Load one ad ahead per format; reload in `adDidDismissFullScreenContent` and after a failed
  present. Never load on the trigger and show when it arrives.
- Loaded ads expire: App Open after **4 h**, interstitial/rewarded ~1 h is a safe refresh
  horizon. Store `loadedAt` and discard stale ads before presenting.
- Retry failed loads with backoff (e.g. 30 s, 60 s, 120 s… cap 10 min). Don't hammer on no-fill.
- Every request carries `npa=1` via `Extras` unless the project has explicitly opted into
  personalized ads (see consent-privacy.md).
- Set `paidEventHandler` on every ad object right after load (analytics.md).
- Present from the top-most presented view controller; if none is available, treat as notReady.
- Full-screen delegate order: `adWillPresentFullScreenContent` → record shown;
  `adDidDismissFullScreenContent` → record dismissed + preload; `ad(_:didFailToPresent…)` →
  preload, report failed.

## App Open

- Trigger: `scenePhase` becomes `.active` (or `sceneWillEnterForeground`) with the measured time
  spent in background. Measure background time yourself (store `Date` on `.background`).
- Never on cold launch of the first sessions (`skipFirstSessions`). On cold launch in later
  sessions, only if an ad is already loaded — don't block a splash waiting for one.
- Don't show if another full-screen ad, a system sheet (share sheet, document picker, camera) or
  the paywall is on screen; returning from those is not "coming back to the app".
- Returning from your own external flow (Safari login, Sign in with Apple, App Store product
  page) must not trigger it — set a suppression flag before leaving.

## Interstitial

- Called only from named triggers at done moments (placement-playbook.md).
- Call `recordCompletion()` on every trigger regardless of outcome — the completion spacing rule
  counts actions, not ads.
- Show *after* the user's result is safely persisted and visible, as they navigate away.

## Rewarded

- Only from an explicit user tap on a button that says what they'll get.
- Set `ServerSideVerificationOptions.userIdentifier` (and optional `customRewardString`) on the
  **loaded ad right before presenting** — it identifies the viewer, not the request.
- See rewarded-ssv.md for crediting. The UI after dismissal polls the server state.

## Rewarded interstitial

- Must be preceded by an intro screen that states the reward and offers a clear way to skip
  (policy). Off by default.

## Native

- See native-ads.md. Request `.native` with a `NativeAdViewAdOptions` (AdChoices corner) and
  `NativeAdMediaAdLoaderOptions` if you need aspect ratio preference.
- The ad unit in the console must be **Native advanced**, not a native banner; mismatched unit
  types never fill.

## Banner

- Off by default. If enabled: anchored adaptive banner sized from the container width, one
  request per visible placement, refresh interval from the console (≥30 s), never overlapping
  controls and never in scroll content that would push/obscure the main action.

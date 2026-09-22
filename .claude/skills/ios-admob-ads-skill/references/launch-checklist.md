# Launch / audit checklist

Report failures in this order: account risk → Apple rejection risk → retention → revenue.

## Account risk (AdMob)
- [ ] Debug resolves every format to Google test units (grep for `#if DEBUG` in `AdUnitIDs`).
- [ ] Test device IDs registered for internal Release/TestFlight testing.
- [ ] No interstitial at launch, exit, tab switch, back, or on every action.
- [ ] `minimumCompletionsBetween` ≥ 2 enforced in code, not only in config.
- [ ] Full-screen cooldown after any full-screen dismissal.
- [ ] Ads preloaded; nothing loads-then-shows on the trigger.
- [ ] Native ads inside `NativeAdView`, labeled, not styled as content, AdChoices unobstructed.
- [ ] Native pool keyed by (placement, slot); no request on cell reuse; ≤55 min cache.
- [ ] Native unit type in console is Native advanced.
- [ ] No user content/PII in any request.
- [ ] Rewarded never credits client-side; SSV enabled on the unit.

## Apple
- [ ] Third-Party Advertising declared; nutrition label lists GMA data types (Tracking = No).
- [ ] No "no ads" claim in metadata.
- [ ] `GADApplicationIdentifier` + `SKAdNetworkItems` present.
- [ ] No ATT prompt unless the tracking package is fully done.
- [ ] UMP message published in console; privacy options entry in Settings when required.

## Retention
- [ ] No ads on work screens.
- [ ] App Open ≥45 s background, skips first sessions, suppressed after own external flows and
      system sheets.
- [ ] Paid entitlement checked separately from master switch; pool cleared on upgrade.
- [ ] Banner off.

## Operability
- [ ] Ships with `ads.enabled = false`; formats enabled remotely one at a time.
- [ ] Unit IDs overridable from Remote Config; Info.plist tier works; constants as last resort.
- [ ] Refusal reasons and impression revenue logged.
- [ ] AdGate tests pass (spacing, caps, day rollover, rows/chunks agreement).

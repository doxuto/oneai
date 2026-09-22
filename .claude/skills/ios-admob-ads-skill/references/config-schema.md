# `ads_config` schema

One Remote Config parameter per domain (`ads_config`, and separately e.g. `review_config`),
each a JSON string. A domain that fails to parse is dropped and keeps **its own** defaults;
other domains are unaffected. Defaults ship in the bundle (`setDefaults`) so the first launch
behaves correctly before any fetch.

**Defaults are always the safe side**: ads off, wide spacing, low caps. A build that can't reach
Remote Config must behave like the mildest build, not the most aggressive.

| Key | Default | Meaning |
|---|---|---|
| `enabled` | **false** | Master switch. Off ⇒ SDK not started, consent not requested |
| `fullScreenCooldownSeconds` | 30 | No full-screen ad of any format within this many seconds of the last full-screen dismissal |
| `appOpen.enabled` | true | |
| `appOpen.minimumBackgroundSeconds` | 45 | Time in background before a return can show App Open |
| `appOpen.minimumSecondsBetween` | 300 | |
| `appOpen.maxPerDay` | 4 | |
| `appOpen.skipFirstSessions` | 3 | First sessions are when people decide whether to keep the app |
| `interstitial.enabled` | true | |
| `interstitial.minimumSecondsBetween` | 180 | |
| `interstitial.minimumCompletionsBetween` | 2 | AdMob: max 1 interstitial per 2 actions. Clamped to ≥2 in code |
| `interstitial.maxPerDay` | 6 | |
| `interstitial.minimumSessionSeconds` | 60 | |
| `interstitial.minimumLifetimeCompletions` | 3 | |
| `native.enabled` | true | |
| `native.placements` | `[]` in the template (fill per app) | Placement **names** allowed to render |
| `native.firstRow` | 6 | 1-based display row of the first ad |
| `native.everyRows` | 10 | Content rows between ads |
| `native.maxPerScreen` | 3 | |
| `banner.enabled` | **false** | |
| `banner.placements` | `[]` | |
| `rewarded.enabled` | true | |
| `rewarded.maxPerDay` | 3 | |
| `rewarded.grantAmount` | 5 | Informational for UI copy only; the **server** clamps the real grant |
| `unitIDs` | `{}` | Override per format key: `appOpen`, `interstitial`, `rewarded`, `rewardedInterstitial`, `native`, `banner` |

## Ad unit ID resolution

`unitIDs` (Remote Config) → `Info.plist` (`GADUnitID_<format>`) → compiled constant. Each step is
skipped when empty, so a half-filled block can never leave a format with no ID. Unknown keys are
**kept**, not rejected — that's how you pre-stage an ID before the build that uses it ships.
Before this existed, "move a placement to a new unit" required shipping a build.

**Debug ignores all three and returns Google's test units.**

## Evolving the schema

- Renaming a key is a **breaking change**: running builds fall back to the default. Add the new
  key, keep reading the old one for a release or two, then drop it.
- Tune thresholds with **console conditions** (country, app version, % of users), not builds.
- Lower `minimumFetchInterval` via a console condition while tuning; default Release interval
  (12 h) makes experiments slow.
- Turn formats on one at a time, and watch uninstall rate + refusal reasons for a week each.

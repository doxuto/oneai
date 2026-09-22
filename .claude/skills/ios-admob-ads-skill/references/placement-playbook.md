# Placement playbook

## Step 1 — classify every screen

- **Work screens**: where the app's core job happens (camera/scanner, editor, reader, player,
  form, checkout, AI result, onboarding). **No ads, ever.** An ad here is exactly AdMob's
  "interferes with main content".
- **Browse screens**: lists, library, history, settings, home feed.
- **Done moments**: the instant a unit of work finishes (saved, exported, level cleared, chapter
  finished) and the user is about to go somewhere else.

Write the classification into the project's docs and get the user to confirm it. The rest of
this file assumes it exists.

## Step 2 — pick formats per location

| Format | Put it | Default spacing | Reason |
|---|---|---|---|
| **Native** | Inside browse lists, first at row 6, then every 10 rows, max 3 per screen | `native.firstRow=6`, `everyRows=10`, `maxPerScreen=3` | Least annoying format. Row 6 is past the first screen: the answer to "where is my stuff" must never be an ad |
| **Native** | Below a "done" result screen | placement name e.g. `exportDone` | Work is finished; user is deciding what next |
| **Interstitial** | On transition *out of* a done moment back to a browse screen | ≥180 s apart, ≥2 completions apart, ≤6/day, not in first 60 s of session, not before 3 lifetime completions | Literally "between content pages" |
| **App Open** | Returning to foreground after ≥45 s in background | ≥300 s apart, ≤4/day, skip first 3 sessions | Most hated format; 45 s is what makes it tolerable |
| **Rewarded** | User-initiated, where a limit is hit ("watch an ad for 5 more uses today") | ≤3/day | The only opt-in format; server credits it |
| **Rewarded interstitial** | Only if the product has a natural "bonus" offer at a done moment, with an opt-out intro screen | off unless asked | Needs an intro with skip per policy |
| **Banner** | Nowhere by default | `banner.enabled=false` | Kept for measurement only |

## Step 3 — write the placement enum

Placements are **names**, not indexes, so Remote Config can turn one off without a build:

```swift
public enum NativePlacement: String, Codable, Sendable, CaseIterable {
    case library, exportDone      // rename per app
}
public enum InterstitialTrigger: String, Codable, Sendable {
    case documentSaved, exportFinished
}
```

Every call site passes its trigger/placement so refusals and impressions are attributable.

## Anti-patterns to reject in review

- Interstitial on tab switch, on back button, on opening a detail screen, on app launch.
- Interstitial shown *before* the result of the user's action (holding their work hostage).
- Native ad styled like a content row (same cell, no label).
- Rewarded that credits locally, or that rewards clicks.
- Any ad on a screen showing the user's own private content (documents, photos, messages).

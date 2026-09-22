# Native ads

## Why it needs its own target

A native ad **must** be rendered inside the SDK's `NativeAdView`, with each asset view registered
(`headlineView`, `bodyView`, `callToActionView`, `iconView`, `mediaView`, …) and `nativeAd`
assigned last. The SDK counts impressions and clicks by observing that view. A custom SwiftUI
card built from the strings earns nothing and shows ad assets outside their container.

That puts the SDK into list view hierarchies. To keep features SDK-free:

| Where | What | Imported by |
|---|---|---|
| DesignSystem | `NativeAdSlot(placement:slot:)` view + `EnvironmentValues.nativeAdRenderer` | Features |
| AdsUI (app target only) | `NativeAdsHost` (injects renderer), `NativeAdPool`, `NativeAdCardView` (UIViewRepresentable wrapping `NativeAdView`) | App |
| AdsCore | `AdGate.native`, `AdGate.nativeRows`, `AdGate.nativeChunks` | All |

When no renderer is in the environment (tests, previews, paid users, ads disabled) the slot
renders **nothing** (`EmptyView`, zero height). That's not a stub — it's exactly what a free user
sees on a no-fill day.

## One rule, two shapes

- `nativeRows(itemCount:config:)` → item indices before which an ad is inserted (for `List` /
  `LazyVStack` / UITableView).
- `nativeChunks(items:config:)` → item arrays between ads (for `LazyVGrid`, which cannot insert a
  full-width row mid-grid: render chunk, ad, chunk, ad, …).

`nativeChunks` is **derived from** `nativeRows`; a test asserts they agree, so the third ad can
never be in different places in list vs grid.

## The pool: one ad per (placement, slot)

- Not a queue. A `NativeAd` may appear in exactly one view, so the second ad on a screen is a
  second request.
- Key by `(placement, slotIndex)` — both stable for a screen's lifetime. Scrolling away and back
  shows the **same** ad; cell reuse never triggers a new request. Requests per session ≈ visible
  slots, which keeps the request/impression ratio healthy.
- Keep an ad at most **55 min** (Google: don't cache over an hour), then replace on next display.
- On no-fill, back off **60 s** for that key before requesting again.
- Clear the pool when the entitlement changes to ad-free.

## The card

- Full-width card **between** content chunks, never disguised as a content row.
- Visible "Ad" badge inside the layout; top-right corner left clear for the SDK's AdChoices icon.
- Clamp media aspect ratio to **1.0–1.91**; a tall creative would push content off screen
  ("ad obscures content"). Hide `mediaView` entirely when the ad reports no aspect ratio — an
  empty media view is a grey rectangle.
- CTA as a non-interactive label inside the registered `callToActionView`
  (`isUserInteractionEnabled = false`) — the SDK handles the click.
- Support Dynamic Type and dark mode like any other card.

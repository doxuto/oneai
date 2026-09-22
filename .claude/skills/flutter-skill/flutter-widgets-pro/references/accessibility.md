# Accessibility

Read this for every screen that ships. Flutter gives most widgets sensible semantics for free, so the work is narrow: label the things that have no text, keep tap targets big enough, let text scale, respect the user's motion and contrast settings, and fix traversal order where the visual order and the widget order disagree.

## The semantics tree

Flutter builds a second tree alongside the render tree and hands it to TalkBack, VoiceOver, Switch Control, and the web accessibility bridge. Inspect it with the DevTools **Semantics** view, `debugDumpSemanticsTree()`, or `SemanticsDebugger`.

Widgets that already carry semantics: `Text`, `Image(semanticLabel:)`, `IconButton(tooltip:)`, every Material button, `TextField`, `Checkbox`, `Switch`, `Slider`, `ListTile`, `AppBar`, `Tab`. Anything hand-built from `GestureDetector` + `Container` carries none — that is the case that needs `Semantics`.

## `Semantics`

```dart
Semantics(
  label: 'Unread messages',
  value: '$count',
  button: true,
  onTap: _open,
  child: ExcludeSemantics(child: _CustomBadge(count: count)),
)
```

Properties worth naming: `label`, `hint`, `value`, `increasedValue`/`decreasedValue`, `button`, `link`, `image`, `textField`, `headingLevel`, `liveRegion`, `checked`, `selected`, `toggled`, `enabled`, `focusable`/`focused`, `obscured`, `readOnly`, `sortKey`, `container`, `explicitChildNodes`, `excludeSemantics`, plus action handlers `onTap`, `onLongPress`, `onIncrease`, `onDecrease`, `onDismiss`, `onScrollLeft`/`Right`/`Up`/`Down`.

Rules:

- A `label` describes what the control *is*, not what it looks like. "Delete note", not "Trash icon". Do not include the role — the platform appends "button" itself.
- `hint` describes the result of acting: "Double tap to open the note".
- `value` is the current reading of a control (a slider's number, a counter). It is announced on change when combined with `liveRegion: true`.
- Wrapping a widget that already has semantics without `excludeSemantics: true` produces two nodes and a double announcement.
- `container: true` forces a new node instead of merging into the parent — use it when a custom widget must be one focusable unit.

## Headings

**Since Flutter 3.47, `Semantics(header: true)` is a no-op on iOS and Android.** Declare headings with `headingLevel`.

```dart
// Before
Semantics(header: true, child: Text('Settings'))

// After
Semantics(headingLevel: 1, child: Text('Settings'))
```

Any integer greater than 0 marks a heading on iOS (`UIAccessibilityTraitHeader` plus `accessibilityHeadingLevel`) and Android (`View.setHeading(true)`). On web, 1–6 map to `<h1>`–`<h6>`. Use 1 for the screen title and 2 for section titles; do not skip levels.

## Merging, excluding, blocking

| Widget | Effect |
|---|---|
| `MergeSemantics` | Collapses the subtree into one node — a row of icon + title + subtitle reads as one item instead of three swipes |
| `ExcludeSemantics` | Removes the subtree from the tree — decorative icons, a duplicated label |
| `BlockSemantics` | Hides everything painted *below* it in the same tree — a modal barrier |
| `IndexedSemantics` | Supplies the index for a list item (`ListView` adds these automatically) |
| `Semantics(explicitChildNodes: true)` | Keeps children as separate nodes under a labelled parent |

```dart
// A custom card that currently reads as four separate swipes.
MergeSemantics(
  child: Row(
    children: <Widget>[
      const ExcludeSemantics(child: Icon(Icons.note)),
      Expanded(child: Text(note.title)),
      Text(note.dateLabel),
    ],
  ),
)
```

Decorative images take `ExcludeSemantics` or `Image(excludeFromSemantics: true)`. Informative ones take `Image(semanticLabel: '...')`.

## Touch targets

- Minimum 48×48 logical pixels (Android) / 44×44 (iOS). `IconButton` and the Material buttons already meet it; a bare `GestureDetector` around a 16 dp icon does not.
- `ThemeData(materialTapTargetSize: MaterialTapTargetSize.padded)` is the default and keeps 48 dp around small controls. `MaterialTapTargetSize.shrinkWrap` removes it — only for a control inside an already-large target.
- Tightening `VisualDensity` shrinks targets. `VisualDensity.compact` on a phone build is a finding.
- Enforce a minimum with `ConstrainedBox(constraints: const BoxConstraints(minWidth: 48, minHeight: 48))` or `minimumSize: const Size(48, 48)` in the button style.
- Targets must not overlap; two adjacent 48 dp targets need their own space, not a shared one.

## Contrast

- WCAG AA: 4.5:1 for body text, 3:1 for text 18 pt or larger and for meaningful non-text (icons, focus rings).
- An M3 `ColorScheme` pairs each role with its `on*` counterpart at a conforming ratio. Contrast failures almost always come from hand-picked colours or from putting `onSurfaceVariant` text on a `primary` background.
- Support the OS high-contrast setting: `MediaQuery.highContrastOf(context)` and a `ColorScheme.fromSeed(contrastLevel: 1.0)` variant. `ThemeData` also accepts `highContrastTheme` and `highContrastDarkTheme` on `MaterialApp`.
- Never convey state by colour alone; pair it with an icon, a label, or a shape.

## Text scaling

```dart
final TextScaler scaler = MediaQuery.textScalerOf(context);
final double scaled = scaler.scale(16);
```

- `TextScaler` replaces the old `double textScaleFactor`; `MediaQuery.of(context).textScaleFactor` and `MediaQuery.textScaleFactorOf` are deprecated. `TextScaler.noScaling`, `TextScaler.linear(x)`, and `scaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.5)` are the useful members. Non-linear system scaling means `textScaleFactor` is only an estimate — do not reconstruct one.
- Never force `TextScaler.noScaling` on user-facing text. If a layout genuinely cannot take 200%, clamp:

```dart
MediaQuery.withClampedTextScaling(
  maxScaleFactor: 1.5,
  child: const _DenseChartLegend(),
)
```

- Layouts must survive large text: avoid fixed-height rows containing text, prefer `Wrap` over `Row` for chips, and test at the largest OS setting plus the bold-text toggle (`MediaQuery.boldTextOf(context)`).
- A fixed `height:` on a `SizedBox` wrapping text is the most common source of overflow at 200% scaling.

## Traversal order and announcements

- Screen-reader order follows the semantics tree, which follows paint order. A `Stack` whose visual order differs from its child order reads out of order.
- Fix with `Semantics(sortKey: const OrdinalSortKey(1))` on each sibling, inside a common parent.
- `SemanticsService.announce(message, textDirection)` for transient events with no visual anchor (a background sync finished). Prefer `liveRegion: true` on the widget that actually changed.
- Route changes are announced automatically when routes have a `semanticLabel`/`barrierLabel`; `showDialog(barrierLabel: ...)` and `ModalRoute` labels matter for dismiss announcements.
- Keyboard focus and screen-reader focus are different. Desktop and web need a visible focus indicator: do not remove `focusColor`/`overlayColor` from the theme.

## Motion and other settings

| Setting | Read with |
|---|---|
| Reduce motion | `MediaQuery.disableAnimationsOf(context)` |
| Bold text | `MediaQuery.boldTextOf(context)` |
| High contrast | `MediaQuery.highContrastOf(context)` |
| Invert colours | `MediaQuery.invertColorsOf(context)` |
| Screen reader active | `MediaQuery.accessibleNavigationOf(context)` |

```dart
final Duration d = MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : const Duration(milliseconds: 300);
```

Respect reduce-motion for parallax, autoplaying carousels, and large transitions; cross-fades are usually acceptable. When `accessibleNavigationOf` is true, avoid time-limited interactions (auto-dismissing snackbars carrying the only copy of an action).

## Checking it

`flutter_test` ships guideline matchers — the mechanics belong to `flutter-testing-pro`, but the four to assert are:

| Guideline | Checks |
|---|---|
| `androidTapTargetGuideline` | Android minimum tappable area |
| `iOSTapTargetGuideline` | iOS minimum tappable area |
| `textContrastGuideline` | WCAG minimum text contrast |
| `labeledTapTargetGuideline` | Every tappable node has a label |

Used as `await expectLater(tester, meetsGuideline(androidTapTargetGuideline));` with a `SemanticsHandle` from `tester.ensureSemantics()`. Manual passes still matter: run TalkBack and VoiceOver on the real screens, set text size to maximum, and turn on bold text and high contrast.

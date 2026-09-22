# Layout: constraints, flex, and reading layout errors

Read this whenever the complaint is an overflow stripe, an "unbounded" assertion, a widget that refuses to size, or an `Expanded`/`Flexible` question. Flutter's layout has exactly one rule and every error message is a restatement of it.

## The one rule

**Constraints go down. Sizes go up. The parent sets the position.**

- A parent passes a `BoxConstraints` (`minWidth`, `maxWidth`, `minHeight`, `maxHeight`) to each child.
- Each child returns a `Size` that satisfies those constraints. It cannot decide where it is, and it cannot know anything about its siblings.
- The parent positions each child and reports its own size upward.

Consequences worth stating out loud, because they are where the confusion lives:

- A widget cannot be "as big as its content" if its parent gave it a tight constraint, and cannot be "as big as its parent" if the parent gave it an unbounded one.
- `Container(width: 100)` is a *request*. `SizedBox`/`Container` wraps the child in an `Align`-like box only if the incoming constraints allow it; under tight constraints the request is ignored. Wrap in `UnconstrainedBox`/`ConstrainedBox` deliberately, or fix the parent.
- There is no way to read your own size during `build`. Use `LayoutBuilder` (constraints, not size), `IntrinsicHeight` (expensive), or measure after layout with a `GlobalKey` + post-frame callback.

## Constraint vocabulary

| Term | Meaning |
|---|---|
| Tight | `min == max` on that axis. The child has no choice. `BoxConstraints.tight(size)` |
| Loose | `min == 0`, `max` finite. The child picks anything up to `max`. `BoxConstraints.loose(size)` |
| Bounded | `max` is finite |
| Unbounded | `max == double.infinity`. Any child that wants to fill will assert |
| Expanded | `min == max == infinity` — what `Expanded` hands its child |

Who hands out unbounded constraints: `ListView`/`SingleChildScrollView` on the scroll axis, `Column` on the vertical axis for non-flex children, `Row` on the horizontal, `Stack` (loose, to non-positioned children it sizes to fit), `UnconstrainedBox`, `OverflowBox`, and any sliver's main axis.

## `Row`, `Column`, `Flex`

Layout algorithm, in order:

1. Lay out every non-flex child with unbounded main-axis constraints (cross-axis constraints depend on `crossAxisAlignment`: `stretch` is tight, everything else is loose).
2. Divide the *remaining* main-axis space among the flex children in proportion to their `flex`.
3. Size self to `mainAxisSize`: `MainAxisSize.max` (default) fills the incoming constraint; `MainAxisSize.min` shrinks to the children.

So: **flex children require a bounded main axis.** A `Column` with an `Expanded` inside a `SingleChildScrollView` asserts, because the scroll view gave the column unbounded height and there is nothing to divide.

| Widget | Constraint it gives the child | Use |
|---|---|---|
| `Expanded` | tight, exactly the share | The child must fill its share |
| `Flexible` (`fit: FlexFit.loose`, the default) | loose, at most the share | The child may be smaller |
| `Flexible(fit: FlexFit.tight)` | identical to `Expanded` | — |
| neither | unbounded on the main axis | Child sizes to content |

```dart
// Before — "A RenderFlex overflowed by 84 pixels on the right."
Row(
  children: <Widget>[
    const Icon(Icons.person),
    Text(user.veryLongDisplayName),
  ],
)

// After — the text gets the leftover width and ellipsises inside it.
Row(
  children: <Widget>[
    const Icon(Icons.person),
    Expanded(
      child: Text(user.veryLongDisplayName, overflow: TextOverflow.ellipsis),
    ),
  ],
)
```

```dart
// Before — "Vertical viewport was given unbounded height."
Column(children: <Widget>[const Header(), ListView.builder(...)])

// After — the list gets the remaining height and keeps recycling.
Column(children: <Widget>[const Header(), Expanded(child: ListView.builder(...))])
```

`shrinkWrap: true` also silences that assertion but makes the list lay out *every* child on every scroll frame. Use it only for a genuinely short, non-scrolling list, and never together with a parent that already scrolls — use slivers instead (`scrolling-and-lists.md`).

## Reading the error messages

| Message | Meaning | Usual fix |
|---|---|---|
| `A RenderFlex overflowed by N pixels on the right/bottom` | Children's natural sizes exceed the flex's bounded main axis | `Expanded`/`Flexible` on the greedy child, `overflow: TextOverflow.ellipsis`, `Wrap`, or make the flex scroll |
| `Vertical viewport was given unbounded height` | A scrollable inside a `Column`/another scrollable | `Expanded`, a fixed `SizedBox` height, or slivers |
| `RenderBox was not laid out` | A follow-on error after an earlier assertion | Fix the *first* error in the log; ignore this one |
| `Incorrect use of ParentDataWidget` | `Expanded`/`Flexible`/`Positioned` whose direct parent is not `Flex`/`Stack` | Remove the intervening widget or move the parent-data widget |
| `BoxConstraints forces an infinite width/height` | Something asked for `double.infinity` under an unbounded parent | Bound it |
| `Cannot hit test a render box that has never been laid out` | Same as "not laid out" — earlier failure | Fix the first error |
| `The following assertion was thrown during performLayout(): ... hasSize` | Reading `size` before layout | Measure in a post-frame callback |

Debugging tools: `debugDumpRenderTree()` prints every `RenderObject` with its constraints and size; the DevTools Layout Explorer shows flex factors and incoming constraints interactively. `debugPaintSizeEnabled = true` outlines boxes.

## `IntrinsicWidth` / `IntrinsicHeight`

These ask every child "how big would you be, ideally?" before laying out, which is a second layout pass and is documented as relatively expensive — for some render objects it is O(N²) in the subtree. Use them for small, fixed subtrees only (equal-width buttons, a table row). For anything list-shaped, precompute a size or use `IntrinsicColumnWidth` inside a `Table`, or restructure so the constraint comes from the parent.

## `Stack` and `Positioned`

- Non-positioned children get loose constraints and are aligned by `Stack.alignment`; the `Stack` sizes itself to the largest of them (under `StackFit.loose`).
- `StackFit.expand` gives non-positioned children tight constraints equal to the stack.
- A `Positioned` child is laid out against the stack's final size and does **not** contribute to it. A `Stack` containing only `Positioned` children collapses to the incoming minimum.
- `Positioned.fill`, `Positioned.directional` (RTL-aware), and `AnimatedPositioned` are the common variants.
- `clipBehavior: Clip.none` lets children paint outside; default is `Clip.hardEdge`.
- `Positioned` outside a `Stack` throws `Incorrect use of ParentDataWidget`.

## `LayoutBuilder`

`LayoutBuilder` gives you the **incoming constraints**, not your size, and its builder runs during layout — so it cannot call `setState` synchronously and cannot be used to read anything that is decided later.

```dart
LayoutBuilder(
  builder: (BuildContext context, BoxConstraints constraints) {
    return constraints.maxWidth >= 720
        ? const _TwoPaneLayout()
        : const _SinglePaneLayout();
  },
)
```

Use it for responsive decisions based on the space actually available (a pane inside a split view), and `MediaQuery.sizeOf` for decisions based on the window. A `LayoutBuilder` on the unbounded axis receives `double.infinity` and is useless there. `SliverLayoutBuilder` is the sliver equivalent.

## `SafeArea` and insets

- `SafeArea` pads its child by `MediaQuery.paddingOf(context)` — notch, status bar, home indicator — and by default consumes that padding so nested `SafeArea`s do not double-pad.
- `SliverSafeArea` is required inside a `CustomScrollView`; a box `SafeArea` cannot be a sliver.
- `MediaQueryData.padding` is the system intrusion after `viewInsets` are subtracted; `viewInsets` is the keyboard (and other occlusions); `viewPadding` is the intrusion ignoring `viewInsets`. To leave room for the keyboard, read `viewInsetsOf(context).bottom`; to avoid the notch, read `paddingOf`.
- Do not hardcode a status-bar height. Do not wrap a `Scaffold` in `SafeArea` — the `Scaffold` already handles the app bar and `bottomNavigationBar`; wrap the `body` instead if needed.

## `MediaQuery` access

`MediaQuery.of(context)` registers a dependency on the whole `MediaQueryData`, so the widget rebuilds when the keyboard opens, the text scale changes, or the brightness flips — even if it only wanted the width. Use the aspect accessors:

| Accessor | Returns |
|---|---|
| `MediaQuery.sizeOf(context)` | `Size` — also `widthOf`, `heightOf` |
| `MediaQuery.paddingOf(context)` | system intrusions |
| `MediaQuery.viewInsetsOf(context)` | keyboard |
| `MediaQuery.viewPaddingOf(context)` | intrusions ignoring `viewInsets` |
| `MediaQuery.textScalerOf(context)` | `TextScaler` |
| `MediaQuery.platformBrightnessOf(context)` | light/dark |
| `MediaQuery.orientationOf(context)` | portrait/landscape |
| `MediaQuery.devicePixelRatioOf(context)` | dpr |
| `MediaQuery.disableAnimationsOf`, `boldTextOf`, `highContrastOf`, `accessibleNavigationOf`, `invertColorsOf` | accessibility settings |

Each has a `maybe*` variant that returns `null` instead of asserting when there is no `MediaQuery` ancestor. `textScaleFactorOf` is deprecated in favour of `textScalerOf`.

To *change* what a subtree sees, wrap it: `MediaQuery.removePadding(context: context, removeTop: true, child: ...)` or `MediaQuery(data: MediaQuery.of(context).copyWith(...), child: ...)`.

## Other sizing widgets worth naming correctly

| Widget | Effect |
|---|---|
| `ConstrainedBox` | Tightens the incoming constraints |
| `UnconstrainedBox` | Lets the child be its natural size (may overflow) |
| `ConstraintsTransformBox` | The general form; `ConstraintsTransformBox.widthUnconstrained` etc. |
| `FittedBox` | Scales/positions a single child into the available space |
| `AspectRatio` | Sizes to a ratio within the constraints |
| `FractionallySizedBox` | A fraction of the incoming maximum |
| `Wrap` | Flow layout — the correct answer to "the `Row` overflows with chips" |
| `Flow` / `CustomMultiChildLayout` | Manual positioning without a full render object |

# Scrolling, lists, and slivers

Read this for anything with a scroll bar: choosing a `ListView` variant, combining a header with a list, pagination, pull to refresh, keeping state alive across scrolls, and the three or four settings that decide whether a list is smooth or not.

## Choosing the widget

| Situation | Use |
|---|---|
| A handful of known children, may overflow | `SingleChildScrollView` + `Column` |
| A long or unbounded homogeneous list | `ListView.builder` |
| Same, with dividers | `ListView.separated` |
| A grid | `GridView.builder` with a `SliverGridDelegate` |
| Header(s), list(s), grid(s), footers in one scroll view | `CustomScrollView` + slivers |
| Collapsing app bar over tabs, each tab scrolling | `NestedScrollView` |
| Horizontal paging | `PageView` |
| Drag to reorder | `ReorderableListView.builder` |
| Two-dimensional scrolling | `TableView` from `package:two_dimensional_scrollables` |

`ListView(children: [...])` builds every child immediately. It is correct only for a small, fixed set. Any list whose length comes from data uses `.builder`.

## `ListView.builder` checklist

```dart
ListView.builder(
  itemCount: notes.length,                       // never null for a finite list
  itemExtent: 72,                                // uniform rows → constant-time offsets
  padding: const EdgeInsets.symmetric(vertical: 8),
  itemBuilder: (BuildContext context, int index) {
    final note = notes[index];
    return NoteTile(key: ValueKey<String>(note.id), note: note);
  },
)
```

- `itemCount: null` means infinite; the scrollbar and `maxScrollExtent` become meaningless. Set it.
- `itemExtent` (fixed height) or `prototypeItem` (a widget whose measured height is used for all rows) lets the viewport compute scroll offsets without laying out intermediate children. Use one whenever rows are uniform; it is the difference between a smooth long-list jump and a stutter.
- `itemBuilder` must be cheap and pure. No network, no sorting, no `DateFormat` construction per row.
- Keys: `ValueKey(model.id)` on each item, so that inserting or removing does not shift `State` between rows.
- `findItemIndexCallback` on `ListView.separated`/`SliverList.separated` maps a child key back to an item index so the framework can keep elements when the list is reordered. **`findChildIndexCallback` is deprecated as of 3.41** — it counted separators, so it needed `index * 2`; `findItemIndexCallback` takes the item index directly.
- `scrollCacheExtent: const ScrollCacheExtent.pixels(500)` or `.viewport(0.5)` — **`cacheExtent`/`cacheExtentStyle` are deprecated as of 3.44.**
- `addAutomaticKeepAlives`, `addRepaintBoundaries`, `addSemanticIndexes` default to `true`. Turn `addRepaintBoundaries` off only when rows are trivially cheap to repaint and you have measured a win.

## Slivers

A sliver lays out lazily against a `SliverConstraints` (scroll offset, remaining paint extent) and reports a `SliverGeometry`. Slivers go in `CustomScrollView.slivers`; boxes do not.

| Sliver | Purpose |
|---|---|
| `SliverList` / `SliverList.builder` / `SliverList.separated` | Lazy linear list |
| `SliverFixedExtentList` | Uniform item extent — cheapest list |
| `SliverPrototypeExtentList` | Extent derived from a prototype child |
| `SliverVariedExtentList` | Per-index extent callback |
| `SliverGrid` / `SliverGrid.builder` | Lazy grid |
| `SliverAppBar`, `.medium`, `.large` | Collapsing app bar; M3 sizes |
| `SliverToBoxAdapter` | Wraps a single box widget as a sliver |
| `SliverList` vs `SliverChildListDelegate` | Prefer the `.builder` constructors |
| `SliverPadding` | Padding in sliver space |
| `SliverSafeArea` | `SafeArea` for slivers |
| `SliverFillRemaining` | Fills the leftover viewport (`hasScrollBody:` matters) |
| `SliverFillViewport` | One child per viewport |
| `SliverPersistentHeader` | Pinned/floating custom header via `SliverPersistentHeaderDelegate` |
| `SliverMainAxisGroup` / `SliverCrossAxisGroup` | Compose slivers along/across the axis (sticky section headers without a delegate) |
| `SliverAnimatedList`, `SliverReorderableList` | Animated and reorderable sliver lists |
| `SliverOpacity`, `SliverIgnorePointer`, `SliverVisibility` | Sliver versions of box wrappers |

```dart
CustomScrollView(
  slivers: <Widget>[
    const SliverAppBar.large(title: Text('Inbox'), pinned: true),
    const SliverToBoxAdapter(child: _FilterChips()),
    SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList.builder(
        itemCount: threads.length,
        itemBuilder: (BuildContext context, int i) =>
            ThreadTile(key: ValueKey<String>(threads[i].id), thread: threads[i]),
      ),
    ),
    const SliverFillRemaining(hasScrollBody: false, child: _EmptyFooter()),
  ],
)
```

Putting a box widget directly in `slivers:` throws `A RenderRebuildDirtyWidget expected a child of type RenderSliver` — wrap it in `SliverToBoxAdapter`. Putting a sliver in a box slot throws the mirror error.

## `ScrollController` and scroll notifications

```dart
late final ScrollController _controller = ScrollController();

@override
void dispose() {
  _controller.dispose();
  super.dispose();
}
```

- One controller per scroll view. Attaching one controller to two attached scrollables throws.
- `_controller.position` is valid only while attached; reading it in `initState` throws. Read it in a listener or a post-frame callback.
- `ScrollPosition` members worth naming: `pixels`, `maxScrollExtent`, `minScrollExtent`, `extentBefore`, `extentAfter`, `extentInside`, `userScrollDirection`, `atEdge`, `outOfRange`.
- `animateTo(offset, duration:, curve:)` and `jumpTo(offset)`; `_controller.position.ensureVisible(renderObject)` or the widget-level `Scrollable.ensureVisible(context)` to scroll a specific child into view.
- For scroll-driven UI (hiding a FAB, changing an app bar), prefer `NotificationListener<ScrollNotification>` or a `ValueNotifier` fed by the controller over `setState` in the listener — the listener fires on every pixel.

```dart
NotificationListener<ScrollEndNotification>(
  onNotification: (ScrollEndNotification n) {
    if (n.metrics.extentAfter < 400) _loadMore();
    return false;          // false = keep bubbling
  },
  child: ListView.builder(...),
)
```

`ScrollNotification` subtypes: `ScrollStartNotification`, `ScrollUpdateNotification`, `OverscrollNotification`, `ScrollEndNotification`, `UserScrollNotification`.

## `NestedScrollView`

Use it when an outer header (a `SliverAppBar`) must collapse while an inner scrollable (a `TabBarView` of lists) scrolls.

```dart
NestedScrollView(
  headerSliverBuilder: (BuildContext context, bool innerBoxIsScrolled) => <Widget>[
    SliverOverlapAbsorber(
      handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
      sliver: const SliverAppBar(pinned: true, forceElevated: true, title: Text('Feed')),
    ),
  ],
  body: TabBarView(children: <Widget>[_Tab(key: PageStorageKey('a')), _Tab(key: PageStorageKey('b'))]),
)
```

- Each inner list must be a `CustomScrollView` with a `SliverOverlapInjector` at the top, or content hides under the pinned app bar.
- Give each inner list a `PageStorageKey` so its offset survives tab switches.
- Do not pass a `controller` to the inner lists; `NestedScrollView` coordinates them.

## Keeping items alive

Off-screen list children are disposed by default. To preserve state (a playing video, an expanded tile, a text field):

```dart
class _TabState extends State<_Tab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);        // required by the mixin
    return ...;
  }
}
```

Keep-alives defeat recycling — every kept item stays in memory and in the element tree. Use them for a handful of items, never for a whole list. `PageStorageKey` is the cheaper option when only the scroll offset matters.

## `ReorderableListView`

```dart
ReorderableListView.builder(
  itemCount: items.length,
  itemBuilder: (BuildContext context, int i) =>
      ListTile(key: ValueKey<String>(items[i].id), title: Text(items[i].label)),
  onReorderItem: (int oldIndex, int newIndex) {
    setState(() {
      final item = items.removeAt(oldIndex);
      items.insert(newIndex, item);
    });
  },
)
```

- Every child **must** have a key; it is asserted.
- `onReorder` is deprecated as of 3.44 in favour of `onReorderItem`, which applies the `if (oldIndex < newIndex) newIndex -= 1` correction for you. Code that uses `onReorderItem` **and** still subtracts one is off by one.
- `buildDefaultDragHandles: false` plus `ReorderableDragStartListener` when only part of the row should start a drag.

## Pull to refresh and pagination

`RefreshIndicator` requires a scrollable descendant that actually scrolls; a short, non-scrolling list needs `physics: const AlwaysScrollableScrollPhysics()`. Its `onRefresh` must return a `Future` that completes when the work is done, or the spinner never stops.

Pagination shape that does not fight the framework:

1. Trigger from `ScrollEndNotification` or a controller listener on `extentAfter < threshold`.
2. Guard with a plain `bool` field (not `setState`) so a burst of notifications fires one request.
3. Append to the list and `setState` (or let the provider emit) once.
4. Render the loading row as the last item (`itemCount: items.length + 1`) rather than a separate widget below the list.

Where the page data comes from is `riverpod-pro`'s problem; only the trigger and the rendering belong here.

## Physics and behaviour

| Class | Effect |
|---|---|
| `BouncingScrollPhysics` | iOS rubber-band |
| `ClampingScrollPhysics` | Android glow |
| `AlwaysScrollableScrollPhysics` | Scrollable even when content fits |
| `NeverScrollableScrollPhysics` | Disable scrolling (inner list inside an outer scroll view) |
| `RangeMaintainingScrollPhysics` | Keeps offset when content is prepended |

`ScrollConfiguration` sets platform behaviour, the scrollbar, the overscroll indicator, and `dragDevices` — adding `PointerDeviceKind.mouse` there is what makes a list drag-scrollable with a mouse on desktop and web.

# Widget-layer performance

Read this when the complaint is jank, a dropped frame, a list that stutters, or "everything rebuilds". The widget layer has four distinct costs — build, layout, paint, and raster — and the fix depends entirely on which one is being paid. Measure first; the DevTools performance overlay tells you which.

## What marks an element dirty

An element rebuilds when any of these happens:

| Trigger | Scope |
|---|---|
| `setState` in its `State` | That element and its entire subtree |
| The parent rebuilt and passed a non-identical widget | That element, unless `Widget.canUpdate` short-circuits |
| An `InheritedWidget` it depends on changed | Every dependent element, anywhere below |
| A `Listenable` it is listening to notified (`AnimatedBuilder`, `ValueListenableBuilder`, `ListenableBuilder`) | The builder's subtree |
| Hot reload | Everything |

A `const` child is skipped because the new widget is *identical* to the old one. That identity check is the cheapest optimisation available, which is why `const` appears in every rule below.

## Scoping rebuilds

The rule: put the state as close to what changes as possible, and keep the unchanging part out of the rebuilt subtree.

```dart
// Before — setState at the screen root rebuilds the app bar, the list, everything.
class _ScreenState extends State<Screen> {
  int _count = 0;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text('Count: $_count')),
        body: const ExpensiveList(),
        floatingActionButton: FloatingActionButton(
          onPressed: () => setState(() => _count++),
          child: const Icon(Icons.add),
        ),
      );
}

// After — only the Text rebuilds.
class _ScreenState extends State<Screen> {
  final ValueNotifier<int> _count = ValueNotifier<int>(0);

  @override
  void dispose() {
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: ValueListenableBuilder<int>(
            valueListenable: _count,
            builder: (BuildContext context, int value, Widget? child) =>
                Text('Count: $value'),
          ),
        ),
        body: const ExpensiveList(),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _count.value++,
          child: const Icon(Icons.add),
        ),
      );
}
```

Techniques, in order of preference:

1. Move the state down into a small `StatefulWidget` that owns only the changing part.
2. `ValueListenableBuilder` / `ListenableBuilder` / `AnimatedBuilder` around the changing part only.
3. `const` on everything that does not depend on the state.
4. A provider with a narrow selector (`riverpod-pro` — `ref.watch(p.select(...))`).

An `InheritedWidget` high in the tree that changes every frame rebuilds every dependent. `MediaQuery.of(context)` is the classic example: use `MediaQuery.sizeOf(context)` so the keyboard opening does not rebuild widgets that only read the width (`layout.md`).

## The `child:` parameter of builders

`AnimatedBuilder`, `ValueListenableBuilder`, `ListenableBuilder`, `TweenAnimationBuilder`, `StreamBuilder`, and `FutureBuilder` all take an optional `child` that is built **once** and handed back to the builder.

```dart
// Before — the whole subtree is rebuilt 60 times a second.
AnimatedBuilder(
  animation: _controller,
  builder: (BuildContext context, Widget? _) => Transform.rotate(
    angle: _controller.value * math.pi,
    child: ExpensiveLogo(),
  ),
)

// After — ExpensiveLogo is built once; only Transform.rotate is rebuilt.
AnimatedBuilder(
  animation: _controller,
  child: const ExpensiveLogo(),
  builder: (BuildContext context, Widget? child) => Transform.rotate(
    angle: _controller.value * math.pi,
    child: child,
  ),
)
```

Prefer the implicit `Animated*` widgets (`AnimatedContainer`, `AnimatedOpacity`, `AnimatedPositioned`, `AnimatedSwitcher`) where they fit; they do the same thing internally without an explicit controller.

## `RepaintBoundary`

Paint is separate from build. A `RepaintBoundary` gives its subtree its own layer, so repainting it does not repaint its siblings and vice versa.

Add one around:

- A continuously animating widget (a progress spinner, a shimmer) that sits inside static content.
- A `CustomPaint` that repaints on its own schedule.
- Anything you will capture with `RenderRepaintBoundary.toImage`.

Do **not** add them everywhere: each boundary is a separate layer with memory and composition cost. `ListView` already wraps items in repaint boundaries (`addRepaintBoundaries: true`).

Diagnose with `debugRepaintRainbowEnabled = true` — a subtree whose outline colour changes every frame is repainting every frame. In DevTools, "Highlight repaints" is the same switch.

## Expensive work in `build`

`build` runs on the UI thread, possibly several times per frame. Anything in the list below is a finding:

| In `build` | Instead |
|---|---|
| Sorting/filtering a list | Memoise in `State` or a provider |
| `jsonDecode`, regex compilation | Precompute; `compute()` for large payloads |
| `DateFormat(...)` construction | A `static final` formatter |
| `MediaQuery.of(context)` when only one field is needed | `MediaQuery.sizeOf` etc. |
| `Theme.of(context)` called five times | Once into a local |
| Building a list of 500 widgets eagerly | `ListView.builder` |
| `Opacity(opacity: 0)` on a big subtree | `Visibility`/`Offstage`, or do not build it |
| `Opacity` for a fade | `AnimatedOpacity`, or `FadeTransition` |
| `ClipRRect` around every list row | `Container(decoration: BoxDecoration(borderRadius: ...))` |

`Opacity`, `ClipPath`, `ShaderMask`, `BackdropFilter`, and `ColorFiltered` all force a save-layer, which is the most expensive thing the raster thread does. `BackdropFilter` over a large area is the single most common cause of raster-thread jank.

## Images

```dart
Image.network(
  url,
  cacheWidth: 320,                       // decode at display size
  filterQuality: FilterQuality.medium,
  loadingBuilder: ...,
  errorBuilder: ...,
)
```

- `cacheWidth` / `cacheHeight` decode the image at the size you will show it. A 4000×3000 photo decoded at full size costs ~48 MB of RAM regardless of the widget's size. `ResizeImage(provider, width:, height:)` is the explicit form.
- `ImageCache` holds decoded images: `PaintingBinding.instance.imageCache.maximumSizeBytes` (default 100 MB). Call `evict` when an image URL's content changed behind the same URL.
- `precacheImage(provider, context)` before a transition avoids a flash; call it from `didChangeDependencies`.
- `cached_network_image` adds disk caching on top; it still needs `memCacheWidth`.
- `gaplessPlayback: true` keeps the previous frame while a new image loads in the same widget.
- `RepaintBoundary` around a fading image avoids repainting its neighbours.

## Shader compilation and startup jank

Impeller (default on iOS, Android, macOS, and — from 3.47 — Windows and Linux) compiles shaders ahead of time, which removes the first-run shader jank that Skia had. If a project still runs Skia (`--no-enable-impeller`), first-run jank on a new animation is expected and `flutter build --bundle-sksl-path` was the mitigation. Do not recommend SkSL warm-up for an Impeller build; it does not apply.

Other startup costs that show up as jank: synchronous work in `main()` before `runApp`, large `const` maps deserialised at startup, and `WidgetsFlutterBinding.ensureInitialized()` followed by a chain of awaited plugin initialisations. Move what you can behind a splash route.

## Measuring

| Tool | Shows |
|---|---|
| Performance overlay (`showPerformanceOverlay: true`) | Two graphs: UI thread (build+layout) and raster thread. A spike in the top graph is Dart work; the bottom is GPU/paint |
| DevTools → Performance → Frame chart | Per-frame breakdown with `Build`/`Layout`/`Paint`/`Raster` timings |
| DevTools → Performance → Track widget builds | Rebuild counts per widget per frame |
| Widget Inspector → Highlight repaints | Repaint rainbow |
| DevTools → Memory | Image cache size, leaks |
| `flutter run --profile` | The only mode worth measuring in — debug builds are 10× slower and unrepresentative |

Debug flags (set in `main()` or a debug-only block):

| Flag | Effect |
|---|---|
| `debugPrintRebuildDirtyWidgets` | Logs every dirty widget built each frame |
| `debugPrintBuildScope` | Also logs the initial mount builds |
| `debugPrintScheduleBuildForStacks` | Stack trace for each dirty-marking |
| `debugProfileBuildsEnabled` | Sends build events to the DevTools timeline |
| `debugProfilePaintsEnabled` | Same for paints |
| `debugRepaintRainbowEnabled` | Colour-cycles repainted layers |
| `debugPaintSizeEnabled` | Outlines boxes |
| `debugPaintLayerBordersEnabled` | Outlines layers |

`debugPrintRebuildDirtyWidgets` produces an enormous log; turn it on around a specific interaction, not for the session.

## Budget

A 60 Hz device gives 16.7 ms per frame; 120 Hz gives 8.3 ms, split between the UI and raster threads. A single `build` that takes 4 ms is already a quarter of the budget on a ProMotion display. When a frame is over budget, read the frame chart before changing code — build-thread and raster-thread fixes have nothing in common.

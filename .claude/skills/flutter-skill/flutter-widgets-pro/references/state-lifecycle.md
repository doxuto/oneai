# State lifecycle and controller ownership

Read this for anything involving `StatefulWidget`: when each callback runs, what may be done in it, who disposes what, and how to survive an `await`. Leaked controllers, `setState` after dispose, and stale `widget.x` copies are the three most common runtime bugs in the widget layer.

## Callback order

| Callback | When | Allowed |
|---|---|---|
| `createState()` | Once, when the element is created | Return the `State`; nothing else |
| `initState()` | Once, after the element is mounted | Create controllers, subscribe, `addPostFrameCallback`. **No** `context` inherited lookups, **no** `setState` |
| `didChangeDependencies()` | Immediately after `initState`, then whenever a depended-on `InheritedWidget` changes | `Theme.of`, `MediaQuery.of`, `Localizations.of`; re-subscribe to something derived from them |
| `build()` | Every frame the element is dirty | Pure widget construction only |
| `didUpdateWidget(oldWidget)` | The parent rebuilt with a new widget of the same type and key | Compare `widget.x` to `oldWidget.x` and reconcile controllers/subscriptions. `setState` is redundant here — a rebuild already follows |
| `deactivate()` | The element is removed from the tree (may be reinserted this frame via a `GlobalKey`) | Unhook things that reference ancestors |
| `dispose()` | The element is gone for good | Dispose controllers, cancel subscriptions, remove observers. `super.dispose()` **last** |

`reassemble()` runs on hot reload only; use it for debug-time invalidation, never for production logic.

## `initState` and the `context` trap

`context` exists in `initState` (the element is mounted) but inherited widgets must not be read there, because no dependency can be registered yet.

```dart
// Before
@override
void initState() {
  super.initState();
  _color = Theme.of(context).colorScheme.primary;   // throws in debug
}

// After
@override
void didChangeDependencies() {
  super.didChangeDependencies();
  _color = Theme.of(context).colorScheme.primary;   // re-runs when the theme changes
}
```

If the work must happen exactly once and needs a fully built tree (showing a dialog, measuring, scrolling to an offset), use a post-frame callback:

```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((Duration _) {
    if (!mounted) return;
    _controller.jumpTo(widget.initialOffset);
  });
}
```

## `didUpdateWidget` — reconciling to new configuration

A copy of `widget.x` taken in `initState` goes stale the moment the parent rebuilds with a different value. Either read `widget.x` directly in `build`, or reconcile in `didUpdateWidget`.

```dart
class VideoTile extends StatefulWidget {
  const VideoTile({super.key, required this.url});
  final String url;
  @override
  State<VideoTile> createState() => _VideoTileState();
}

class _VideoTileState extends State<VideoTile> {
  late Player _player = Player(widget.url);

  @override
  void didUpdateWidget(VideoTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _player.dispose();                // old one first
      _player = Player(widget.url);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
```

The same shape applies to an externally supplied controller:

```dart
@override
void didUpdateWidget(MyWidget oldWidget) {
  super.didUpdateWidget(oldWidget);
  if (oldWidget.controller != widget.controller) {
    oldWidget.controller.removeListener(_onChange);
    widget.controller.addListener(_onChange);
  }
}
```

## `setState` rules

- Only mutate state **inside** the closure. `setState(() {})` with the mutation outside works but hides the intent and defeats review.
- Never call it from `build`, from `dispose`, or synchronously during layout/paint (for example from a `ScrollController` listener that fires mid-layout — schedule instead).
- Never call it after `dispose`: `if (!mounted) return;` first.
- Do not call it for something that is not rendered. A field that only feeds a callback (`_loadingMore` in a pagination guard) needs a plain assignment.
- `setState` marks the whole element dirty. If only a leaf changed, move the state into that leaf or use a `ValueNotifier` (`performance.md`).

## `mounted` and async gaps

Every `await` is a point at which the widget may have been disposed. After it, `context` is invalid and `setState` throws.

```dart
// Before — three ways to crash.
Future<void> _save() async {
  await repository.save(_draft);
  setState(() => _saved = true);
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
  Navigator.of(context).pop();
}

// After — capture context-derived objects first, then re-check mounted.
Future<void> _save() async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  await repository.save(_draft);
  if (!mounted) return;
  setState(() => _saved = true);
  messenger.showSnackBar(const SnackBar(content: Text('Saved')));
  navigator.pop();
}
```

`ScaffoldMessengerState` and `NavigatorState` remain usable after the calling widget is gone, which is exactly why capturing them before the await is correct and re-reading `context` after it is not. This is the `use_build_context_synchronously` lint; do not silence it with `// ignore:`.

Inside a `State`, `mounted` is `State.mounted`. Outside one, `BuildContext.mounted` (Flutter 3.7+) is the equivalent check for a captured context.

## Controller ownership

| Controller | Created in | Disposed in | Notes |
|---|---|---|---|
| `TextEditingController` | `initState` | `dispose` | Never in `build`; text is lost and instances leak |
| `ScrollController` | `initState` | `dispose` | Remove listeners before disposing |
| `AnimationController` | `initState` with `vsync: this` | `dispose` | Needs `SingleTickerProviderStateMixin` (one) or `TickerProviderStateMixin` (several) |
| `FocusNode` | `initState` | `dispose` | One per field; do not share |
| `PageController` | `initState` | `dispose` | |
| `TabController` | `initState` with `vsync: this` | `dispose` | Or use `DefaultTabController`, which owns it for you |
| `ValueNotifier` / `ChangeNotifier` | `initState` | `dispose` | |
| `StreamSubscription` | `initState` / `didChangeDependencies` | `dispose` via `cancel()` | |

The ownership rule: **whoever constructs it, disposes it.** A widget that receives a controller as a constructor parameter must not dispose it, and must handle the parameter changing in `didUpdateWidget`. A widget that may either receive one or make its own tracks that:

```dart
class SearchField extends StatefulWidget {
  const SearchField({super.key, this.controller});
  final TextEditingController? controller;
  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  TextEditingController? _internal;
  TextEditingController get _effective => widget.controller ?? _internal!;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) _internal = TextEditingController();
  }

  @override
  void dispose() {
    _internal?.dispose();       // only ever the one we made
    super.dispose();
  }
}
```

`CurvedAnimation` is also disposable and is a documented leak source — dispose it alongside its controller.

## `WidgetsBindingObserver`

For app lifecycle, metrics, locale, and accessibility-setting changes:

```dart
class _HomeState extends State<Home> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:  _resumePolling();
      case AppLifecycleState.inactive: break;
      case AppLifecycleState.hidden:   break;
      case AppLifecycleState.paused:   _pausePolling();
      case AppLifecycleState.detached: _pausePolling();
    }
  }
}
```

Other hooks on the same mixin: `didChangeMetrics` (window size/insets), `didChangePlatformBrightness`, `didChangeTextScaleFactor`, `didChangeLocales`, `didChangeAccessibilityFeatures`, `didRequestAppExit`. `AppLifecycleListener` is the newer, disposable, callback-based alternative when you need only one or two of these.

Forgetting `removeObserver` keeps the whole `State` alive for the process lifetime. Treat a missing `removeObserver` as a leak finding.

## Post-frame callbacks

`WidgetsBinding.instance.addPostFrameCallback` runs once, after the current frame is done. Use it for: showing a dialog after the first build, scrolling to an item, measuring a `RenderBox`, or calling `setState` in response to something that fired during layout. Always re-check `mounted` inside it — the callback outlives dispose.

`SchedulerBinding.instance.addPostFrameCallback` is the same binding method; either spelling is fine. A post-frame callback that itself calls `setState` every frame is an infinite build loop; guard it.

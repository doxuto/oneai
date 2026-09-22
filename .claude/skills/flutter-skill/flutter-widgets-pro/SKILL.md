---
name: flutter-widgets-pro
description: Writes, reviews, and refactors the Flutter 3.47 widget layer — composition, layout, lifecycle, rebuild correctness, Material 3, navigation, and accessibility. Use when reading, writing, or reviewing code that uses StatelessWidget, StatefulWidget, BuildContext, Key, GlobalKey, setState, initState, dispose, LayoutBuilder, MediaQuery, ListView, CustomScrollView, slivers, ThemeData, ColorScheme, ThemeExtension, go_router, PopScope, Form, Semantics, or RepaintBoundary, or when the user mentions rebuilds, RenderFlex overflow, unbounded constraints, Material 3 theming, navigation, jank, or accessibility.
license: MIT
metadata:
  author: doxuto
  version: "1.0"
  targets: "Flutter 3.47.5, Dart 3.13.4, material_ui 1.3.x / cupertino_ui 1.x, go_router 18.0.x"
---

Write and review the Flutter widget layer for composition, layout correctness, lifecycle safety, rebuild scope, Material 3 conformance, navigation, and accessibility. Report only genuine problems — do not nitpick or invent issues.

## Core principles

1. **Widgets are immutable configuration; Elements hold the state.** A `Widget` is a description that Flutter throws away and rebuilds constantly. Cost lives in `Element` reconciliation and `RenderObject` layout, not in allocating widgets. This is why `const` constructors, stable `Key`s, and narrow rebuild scopes matter and micro-optimising `build` bodies does not.
2. **`build` is pure and may run at any time.** No I/O, no `setState`, no controller creation, no `Navigator` calls, no mutation of anything outside the frame. Anything with a lifetime belongs in `State` and must be created in `initState` and released in `dispose`.
3. **Constraints go down, sizes go up, the parent sets position.** A widget cannot know its own size; it can only report a size for the constraints it was given. Every `RenderFlex overflowed` and `unbounded height` error is a violated invariant in this model, not a styling problem.
4. **Every controller you create, you dispose.** `TextEditingController`, `ScrollController`, `AnimationController`, `FocusNode`, `PageController`, `TabController`. Controllers passed in from outside are disposed by whoever created them — never by the receiving widget.
5. **Rebuild the smallest subtree that changed.** Split widgets rather than wrapping a whole screen in a builder. Prefer `MediaQuery.sizeOf(context)` over `MediaQuery.of(context)`, `ValueListenableBuilder` with a cached `child:` over a full rebuild, and a separate `StatefulWidget` over a `setState` at the top of a screen.
6. **Theme once, at `ThemeData`; never hardcode colour or type.** `ColorScheme.fromSeed`, M3 colour roles, `TextTheme` M3 names, and component themes. A widget that names `Colors.blue` or a literal `TextStyle` is unthemed and will be wrong in dark mode.
7. **Flutter 3.47 decoupled Material and Cupertino into packages.** New code imports `package:material_ui/material_ui.dart` and `package:cupertino_ui/cupertino_ui.dart`. `package:flutter/material.dart` still compiles but is frozen (since 3.44) and scheduled for formal deprecation in an upcoming stable release, and it produces type mismatches against migrated packages such as go_router 18.

## Review process

1. Check widget structure, `const` usage, keys, and build purity using `references/widget-fundamentals.md`.
2. Check `State` lifecycle, controller ownership, disposal, and `mounted` after async gaps using `references/state-lifecycle.md`.
3. Check layout constraints, flex, overflow, and `MediaQuery` access using `references/layout.md`.
4. Check lists, slivers, scroll controllers, and list performance using `references/scrolling-and-lists.md`.
5. Check `ThemeData`, colour roles, typography, and component themes using `references/material3-theming.md`.
6. Check routing, `go_router` configuration, deep links, and back handling using `references/navigation.md`.
7. Check rebuild scope, repaint boundaries, image decode, and jank using `references/performance.md`.
8. Check forms, validation, focus, keyboard insets, and gestures using `references/forms-and-input.md`.
9. Check semantics, touch targets, contrast, and text scaling using `references/accessibility.md`.
10. Flag any removed, renamed, or hallucinated widget API using `references/common-mistakes.md`.

If doing a partial review, load only the relevant reference files.

## Core instructions

- Target Flutter 3.47.5 / Dart 3.13.4. Import Material from `package:material_ui/material_ui.dart` and Cupertino from `package:cupertino_ui/cupertino_ui.dart`; `package:flutter/widgets.dart`, `/rendering.dart`, `/services.dart`, `/foundation.dart` are unchanged and still ship in the SDK. Migrate existing code with `dart fix --apply --code=migrate_design_widgets`.
- Mark every widget constructor `const` where the fields allow it, and use `const` at every call site that has no runtime values. A `const` widget is canonicalised, compares identical on rebuild, and short-circuits `Element.update` — it is the cheapest optimisation available.
- Extract a subtree into a `StatelessWidget` class, not a `Widget _buildFoo()` helper method. A helper returns a subtree that belongs to the caller's `Element`, so it rebuilds whenever the caller does, cannot be `const`, and gets no `RepaintBoundary` or diagnostics node of its own.
- Add a `Key` only when identity must survive reordering, insertion, or removal among siblings of the same type: `ValueKey` for a stable domain id, `ObjectKey` for identity of an instance without a stable id, `UniqueKey` only to force a teardown. `GlobalKey` is for cross-tree access (`FormState`, `ScaffoldMessengerState`, a branch `Navigator`) and is expensive — never one per list item.
- Create controllers in `initState`, dispose them in `dispose`, and call `super.dispose()` last. React to a changed `widget.x` in `didUpdateWidget` (comparing against `oldWidget.x`), not in `build`. Use `didChangeDependencies` only for work that depends on an inherited widget.
- After any `await` inside a `State` method, check `if (!mounted) return;` before `setState`, `Navigator`, `ScaffoldMessenger`, or `Theme.of`. Capture `BuildContext`-derived objects (`messenger`, `router`, `navigator`) *before* the await instead of reading `context` after it — this is what `use_build_context_synchronously` flags.
- Never call `setState` in `build`, in `dispose`, or from a listener that fires during layout. For "do this once after the first frame", use `WidgetsBinding.instance.addPostFrameCallback` in `initState` and re-check `mounted` inside the callback.
- Use `Expanded` when a flex child must consume the remaining main-axis space and `Flexible` when it may take less. A `Column` inside a `Column`, a `ListView` inside a `Column`, or a `TextField` inside an unbounded `Row` needs `Expanded`/`Flexible` or a bounded parent — not `shrinkWrap: true`, which disables viewport recycling.
- Prefer `MediaQuery.sizeOf`, `.paddingOf`, `.viewInsetsOf`, `.textScalerOf`, `.platformBrightnessOf` over `MediaQuery.of(context)`; the latter subscribes to every `MediaQueryData` field, so the keyboard opening rebuilds widgets that only read the width.
- Build long lists with `ListView.builder`/`.separated` or `SliverList.builder`, never a literal `children:` list of mapped items. Give each item a `ValueKey` derived from the model id. Set `itemExtent` or `prototypeItem` when rows are a uniform height so the viewport can compute scroll offsets without laying out children.
- Use `scrollCacheExtent: const ScrollCacheExtent.pixels(n)` — `cacheExtent` and `cacheExtentStyle` are deprecated as of 3.41. Use `findItemIndexCallback` on `ListView.separated`/`SliverList.separated`; `findChildIndexCallback` is deprecated and its indices counted separators. Use `onReorderItem` on `ReorderableListView`; `onReorder`, which required the manual `if (oldIndex < newIndex) newIndex -= 1` fix-up, is deprecated.
- Build `ThemeData` from `ColorScheme.fromSeed(seedColor: ..., brightness: ...)` and read colour only as a role: `colorScheme.surfaceContainerHigh`, `colorScheme.onSurfaceVariant`, `colorScheme.outlineVariant`. `background`, `onBackground`, and `surfaceVariant` are deprecated — use `surface`, `onSurface`, `surfaceContainerHighest`.
- Read type only as `Theme.of(context).textTheme.titleLarge` etc. The 2018/2021 names (`headline6`, `bodyText2`, `subtitle1`, `caption`, `button`, `overline`) are gone; the M3 set is `display/headline/title/body/label` × `Large/Medium/Small`.
- Use `.withValues(alpha: 0.5)` on `Color`; `.withOpacity` is deprecated for precision loss. Use `MediaQuery.textScalerOf(context)` and `TextScaler`; `textScaleFactor`/`textScaleFactorOf` are deprecated.
- Handle back gestures with `PopScope(canPop: ..., onPopInvokedWithResult: (didPop, result) {...})`. `WillPopScope` is deprecated and breaks Android predictive back; `onPopInvoked` is deprecated in favour of `onPopInvokedWithResult`.
- Declare navigation once in a `GoRouter` passed to `MaterialApp.router(routerConfig: ...)`. Guard with a top-level `redirect`, keep per-tab state with `StatefulShellRoute.indexedStack`, and pass ids in the path — never a whole model object through `extra`.
- Label every interactive widget that has no visible text (`IconButton.tooltip`, `Semantics(label:)`), give every tap target at least 48×48 logical pixels, mark headings with `Semantics(headingLevel: 1)` rather than `header: true` (a no-op on iOS and Android since 3.47), and never disable text scaling.
- State management beyond `setState` belongs to `riverpod-pro`; the Dart language itself belongs to `dart-pro`; widget tests belong to `flutter-testing-pro`. Do not restate their rules — hand off.

## Canonical example

`lib/features/notes/notes_screen.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'note.dart';
import 'note_tile.dart';

/// Owns the scroll controller and the pagination trigger.
/// Data loading itself is a provider — see `riverpod-pro`.
class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key, required this.notes, required this.onLoadMore});

  final List<Note> notes;
  final Future<void> Function() onLoadMore;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  late final ScrollController _controller;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore) return;
    final position = _controller.position;
    if (position.pixels < position.maxScrollExtent - 400) return;
    _loadingMore = true;
    widget.onLoadMore().whenComplete(() {
      if (!mounted) return;      // the screen may be gone by now
      _loadingMore = false;
    });
  }

  Future<void> _refresh() async {
    final messenger = ScaffoldMessenger.of(context); // captured before the await
    try {
      await widget.onLoadMore();
    } on Exception {
      messenger.showSnackBar(const SnackBar(content: Text('Could not refresh')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: CustomScrollView(
          controller: _controller,
          slivers: <Widget>[
            const SliverAppBar.large(title: Text('Notes')),
            SliverSafeArea(
              top: false,
              sliver: SliverList.separated(
                itemCount: widget.notes.length,
                findItemIndexCallback: (Key key) {
                  final id = (key as ValueKey<String>).value;
                  final i = widget.notes.indexWhere((Note n) => n.id == id);
                  return i == -1 ? null : i;
                },
                itemBuilder: (BuildContext context, int index) {
                  final note = widget.notes[index];
                  return NoteTile(key: ValueKey<String>(note.id), note: note);
                },
                separatorBuilder: (BuildContext context, int index) =>
                    const Divider(height: 1),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => const NewNoteRoute().push<void>(context),
        tooltip: 'New note',
        child: const Icon(Icons.add),
      ),
    );
  }
}
```

`lib/features/notes/note_tile.dart` — a separate `const`-able widget, not a `_buildTile` helper:

```dart
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'note.dart';

class NoteTile extends StatelessWidget {
  const NoteTile({super.key, required this.note});

  final Note note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      title: Text(note.title, style: theme.textTheme.titleMedium),
      subtitle: Text(
        note.body,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: note.pinned
          ? Icon(Icons.push_pin, color: theme.colorScheme.primary)
          : null,
      onTap: () => NoteRoute(id: note.id).go(context),
    );
  }
}
```

`lib/app.dart` — theme and router declared once:

```dart
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'router.dart';

class App extends StatelessWidget {
  const App({super.key});

  static const Color _seed = Color(0xFF3A5AFE);

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      routerConfig: appRouter,
      themeMode: ThemeMode.system,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }

  static ThemeData _theme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      listTileTheme: ListTileThemeData(
        iconColor: scheme.onSurfaceVariant,
        minVerticalPadding: 12,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
      ),
    );
  }
}
```

The `Note` model, its `sealed` result type, and the provider that loads pages belong to `dart-pro` and `riverpod-pro` respectively; widget tests for this screen belong to `flutter-testing-pro` → `references/widget-tests.md`.

## Output format

If the user asks for a review, organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated.
3. Show a brief before/after code fix.

Skip files with no issues. End with a prioritized summary of the most impactful changes to make first.

If the user asks you to write or improve code, follow the same rules but make the changes directly instead of returning a findings report.

Example output:

### lib/features/notes/notes_screen.dart

**Line 41: `TextEditingController` created in `build` — a new controller every rebuild, so the field loses its text and the old controllers are never disposed.**

```dart
// Before
@override
Widget build(BuildContext context) {
  final controller = TextEditingController(text: widget.note.title);
  return TextField(controller: controller);
}

// After
late final TextEditingController _title =
    TextEditingController(text: widget.note.title);

@override
void dispose() {
  _title.dispose();
  super.dispose();
}

@override
Widget build(BuildContext context) => TextField(controller: _title);
```

**Line 77: `context` used after an `await` with no `mounted` check — throws if the user navigated away while the request was in flight.**

```dart
// Before
await save();
ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));

// After
final messenger = ScaffoldMessenger.of(context);
await save();
if (!mounted) return;
messenger.showSnackBar(const SnackBar(content: Text('Saved')));
```

### Summary

1. **Correctness (high):** The controller on line 41 is recreated every frame; text input is lost on any rebuild and controllers leak.
2. **Crash (high):** The post-await `context` use on line 77 throws when the screen is disposed mid-request.

End of example.

## References

- `references/widget-fundamentals.md` — Widget/Element/RenderObject, `StatelessWidget` vs `StatefulWidget`, `const` constructors and canonicalisation, `build` purity, `Key`/`ValueKey`/`ObjectKey`/`UniqueKey`/`GlobalKey` decision table, helper method vs widget class, `InheritedWidget` and `BuildContext` lookup.
- `references/state-lifecycle.md` — `createState`, `initState`, `didChangeDependencies`, `didUpdateWidget`, `deactivate`, `dispose`, `setState` rules, `mounted` after async gaps, `use_build_context_synchronously`, controller ownership and disposal, `WidgetsBindingObserver`, `addPostFrameCallback`, `AppLifecycleState`.
- `references/layout.md` — constraints down / sizes up / parent sets position, `BoxConstraints`, `Row`/`Column`/`Flex`, `Expanded` vs `Flexible`, `mainAxisSize`, `IntrinsicWidth`/`IntrinsicHeight` cost, `Stack`/`Positioned`, `LayoutBuilder`, `SafeArea`, `MediaQuery.sizeOf`/`paddingOf`/`viewInsetsOf`, reading "RenderFlex overflowed" and unbounded-constraint errors.
- `references/scrolling-and-lists.md` — `ListView` variants, `.builder` vs literal children, `shrinkWrap`, `CustomScrollView` and a sliver table, `ScrollController`/`ScrollPosition`/`NotificationListener`, `NestedScrollView`, `AutomaticKeepAliveClientMixin`, `ReorderableListView.onReorderItem`, `RefreshIndicator`, pagination, `itemExtent`/`prototypeItem`, `scrollCacheExtent`.
- `references/material3-theming.md` — `ThemeData`, `ColorScheme.fromSeed`, `DynamicSchemeVariant`, the M3 colour-role table, `TextTheme` M3 names, component themes, dark mode, `Theme.of` vs `ThemeExtension`, `MaterialUiCompatibilityBridge`, adaptive widgets, `VisualDensity`, shapes.
- `references/navigation.md` — `Navigator` 1.0 vs the Router API, `go_router` 18 configuration, `GoRoute`, `ShellRoute`, `StatefulShellRoute.indexedStack`, `redirect` and `onEnter`, typed routes with `go_router_builder`, deep links, passing and returning data, nested navigators, `PopScope`/`onPopInvokedWithResult`, `restorationScopeId`.
- `references/performance.md` — what marks an element dirty, scoping rebuilds, `const`, `RepaintBoundary`, `ValueListenableBuilder`/`AnimatedBuilder` `child:` caching, expensive `build` work, image `cacheWidth` and `ResizeImage`, shader/jank basics, DevTools timeline, rebuild/repaint counters, `debugPrintRebuildDirtyWidgets` and friends.
- `references/forms-and-input.md` — `Form`/`FormState`/`FormField`/`TextFormField`, `validator` and `autovalidateMode`, `TextEditingController` ownership, `FocusNode`/`FocusScope`/`onSubmitted`, keyboard insets and `resizeToAvoidBottomInset`, `TextInputFormatter`, `GestureDetector` vs `InkWell`, hit testing and `HitTestBehavior`.
- `references/accessibility.md` — `Semantics` properties, `headingLevel` vs `header`, merging and excluding, `MergeSemantics`/`ExcludeSemantics`/`BlockSemantics`, minimum touch targets, contrast, `MediaQuery.textScalerOf` and `TextScaler.clamp`, traversal order and `OrdinalSortKey`, `disableAnimationsOf`, `boldTextOf`, accessibility guideline matchers.
- `references/common-mistakes.md` — removed, renamed, and hallucinated widget APIs with the correct replacement, plus the recurring structural bugs (controller in `build`, `setState` after dispose, `ListView` in `Column`, `GlobalKey` per item, hardcoded colours).

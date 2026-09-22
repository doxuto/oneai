# Navigation and routing

Read this for route declaration, deep links, tab-preserving navigation, passing and returning data, and back-gesture handling. The default answer for a new app is a single `GoRouter` in `MaterialApp.router`; `Navigator.push` remains correct for local, non-addressable pushes such as a dialog-like editor.

## Navigator 1.0 vs the Router API

| | Navigator 1.0 | Router API (`go_router`) |
|---|---|---|
| Declaration | Imperative `push`/`pop` at call sites | Declarative route table in one place |
| URL / deep links | `onGenerateRoute` string parsing | Path patterns with parameters |
| Browser back / web URLs | Poor | Native |
| Nested per-tab stacks | Manual `Navigator` widgets | `StatefulShellRoute` |
| Redirects / auth gating | Ad hoc | `redirect` / `onEnter` |
| State restoration | `Navigator.restorablePush` variants | `restorationScopeId` |

`Navigator.push(context, MaterialPageRoute(builder: ...))` is still the right tool for a route that is not addressable and has no deep link — a picker sheet, a crop screen. Everything a user could land on from a notification or a link goes in the router.

`MaterialApp` named routes (`routes:`, `onGenerateRoute:`, `Navigator.pushNamed`) are the worst of both worlds: strings with no type safety, no nesting, and manual argument casts. Do not add them to new code.

## `go_router` 18

Verified against pub.dev: current major is **18.0.x**, and it depends on `material_ui ^1.0.0` and `cupertino_ui ^1.0.0` — an app on go_router 18 must be migrated to the standalone design packages (`material3-theming.md`).

```dart
import 'package:go_router/go_router.dart';

final GlobalKey<NavigatorState> _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final GoRouter appRouter = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/notes',
  debugLogDiagnostics: true,
  refreshListenable: authChangeNotifier,     // re-runs redirect when auth changes
  redirect: (BuildContext context, GoRouterState state) {
    final bool signedIn = auth.isSignedIn;
    final bool onSignIn = state.matchedLocation == '/sign-in';
    if (!signedIn && !onSignIn) return '/sign-in?from=${state.uri}';
    if (signedIn && onSignIn) return '/notes';
    return null;                              // null = no redirect
  },
  errorBuilder: (BuildContext context, GoRouterState state) =>
      ErrorScreen(error: state.error),
  routes: <RouteBase>[
    GoRoute(path: '/sign-in', builder: (_, __) => const SignInScreen()),
    GoRoute(
      path: '/notes',
      builder: (BuildContext context, GoRouterState state) => const NotesScreen(),
      routes: <RouteBase>[
        GoRoute(
          path: ':id',                        // → /notes/abc123
          builder: (BuildContext context, GoRouterState state) =>
              NoteScreen(id: state.pathParameters['id']!),
        ),
      ],
    ),
  ],
);

MaterialApp.router(routerConfig: appRouter);
```

`GoRouter` constructor parameters: `routes` (required), `initialLocation`, `redirect`, `refreshListenable`, `errorBuilder`, `errorPageBuilder`, `navigatorKey`, `debugLogDiagnostics`, `observers`, `restorationScopeId`, `onException`, `onEnter`, `redirectLimit`, `routerNeglect`, `overridePlatformDefaultLocation`, `requestFocus`, `extraCodec`.

Navigation methods: `go`, `goNamed`, `push`, `pushNamed`, `pushReplacement`, `pushReplacementNamed`, `replace`, `replaceNamed`, `pop`, `canPop`, `namedLocation`, `refresh`, `restore`. The `context` extensions mirror them: `context.go('/notes')`, `context.push('/notes/1')`, `context.pop()`.

`go` replaces the whole stack with the one implied by the path; `push` adds one route on top. Use `go` for tab switches and post-login landing, `push` for drilling in when you want the platform back gesture to return to exactly where you were.

## `GoRouterState`

| Member | Contains |
|---|---|
| `state.pathParameters` | `Map<String, String>` from `:id` segments |
| `state.uri.queryParameters` | Query string |
| `state.extra` | An arbitrary object passed to `go`/`push` |
| `state.matchedLocation` | The route pattern that matched |
| `state.fullPath` | The configured path of the matched route |
| `state.name` | The route's `name:` |
| `state.error` | Set inside `errorBuilder` |
| `state.pageKey` | `ValueKey<String>` for the page |

`extra` is not encoded in the URL, so a deep link or a web reload loses it and it defeats state restoration unless you supply an `extraCodec`. Pass an **id** in the path and load the object on the destination. Treat "passes a whole model through `extra`" as a finding.

## Shell routes and tabs

`ShellRoute` wraps its children in shared chrome with a single inner `Navigator`. `StatefulShellRoute.indexedStack` gives each branch its **own** `Navigator`, so each tab keeps its stack and scroll position.

```dart
StatefulShellRoute.indexedStack(
  builder: (BuildContext context, GoRouterState state, StatefulNavigationShell shell) =>
      ScaffoldWithNavBar(shell: shell),
  branches: <StatefulShellBranch>[
    StatefulShellBranch(routes: <RouteBase>[GoRoute(path: '/notes', builder: ...)]),
    StatefulShellBranch(routes: <RouteBase>[GoRoute(path: '/search', builder: ...)]),
    StatefulShellBranch(routes: <RouteBase>[GoRoute(path: '/settings', builder: ...)]),
  ],
)

class ScaffoldWithNavBar extends StatelessWidget {
  const ScaffoldWithNavBar({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: shell,
        bottomNavigationBar: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (int i) =>
              shell.goBranch(index: i, initialLocation: i == shell.currentIndex),
          destinations: const <NavigationDestination>[...],
        ),
      );
}
```

- `goBranch(index:, initialLocation: true)` resets that branch to its root — the platform convention for tapping the already-selected tab.
- A route that must cover the tab bar sets `parentNavigatorKey: _rootKey` so it is pushed on the root `Navigator` instead of the branch one.
- `StatefulShellBranch` takes `routes`, a `navigatorKey`, an optional `initialLocation`, `observers`, and `restorationScopeId`.
- go_router 17 made shell-route navigation notify the root observers by default; `notifyRootObserver` controls it.

## Typed routes

`go_router_builder` generates a mixin per route class, removing string paths and manual parameter parsing.

```dart
// lib/router.dart
import 'package:go_router/go_router.dart';

part 'router.g.dart';

@TypedGoRoute<NotesRoute>(
  path: '/notes',
  routes: <TypedGoRoute<GoRouteData>>[TypedGoRoute<NoteRoute>(path: ':id')],
)
@immutable
class NotesRoute extends GoRouteData with _$NotesRoute {
  const NotesRoute();

  @override
  Widget build(BuildContext context, GoRouterState state) => const NotesScreen();
}

@immutable
class NoteRoute extends GoRouteData with _$NoteRoute {
  const NoteRoute({required this.id, this.highlight});

  final String id;            // path parameter, matched by name
  final String? highlight;    // becomes a query parameter

  @override
  Widget build(BuildContext context, GoRouterState state) => NoteScreen(id: id);
}

// Navigating
const NoteRoute(id: 'abc123').go(context);
await const NoteRoute(id: 'abc123').push<bool>(context);
```

- The mixin is `_$RouteClassName` (go_router_builder 3.x). Run `dart run build_runner build --delete-conflicting-outputs`.
- A subclass must override at least one of `build`, `buildPage`, or `redirect`. `onExit` guards leaving a route (unsaved-changes prompts).
- `GoRouteData` also exposes `location`, `go`, `push`, `pushReplacement`, `replace`.
- Use `TypedShellRoute` / `TypedStatefulShellRoute` for shells and `$extra` for non-URL parameters (with the same caveats as `extra`).

## Returning data

```dart
// Push and await a result
final bool? saved = await context.push<bool>('/notes/$id/edit');

// On the editor screen
context.pop(true);
```

`push` returns a `Future<T?>` that completes with the value passed to `pop`. `go` does not return anything, because it replaces the stack. With Navigator 1.0 the equivalent is `Navigator.push<T>` / `Navigator.pop(context, value)`.

## Back handling — `PopScope`

```dart
PopScope<bool>(
  canPop: !_hasUnsavedChanges,
  onPopInvokedWithResult: (bool didPop, bool? result) async {
    if (didPop) return;
    final bool discard = await _confirmDiscard() ?? false;
    if (!mounted || !discard) return;
    Navigator.of(context).pop(result);
  },
  child: _EditorBody(),
)
```

- `WillPopScope` is deprecated and does not work with Android predictive back. `PopScope` is the replacement.
- `onPopInvoked` is deprecated in favour of `onPopInvokedWithResult(bool didPop, T? result)`.
- `canPop` is evaluated *before* the gesture, which is what lets Android render the predictive-back animation. A `canPop: true` plus a "block it in the callback" scheme does not work — set `canPop: false` when you may block.
- `NavigatorPopHandler` wraps a nested `Navigator` so a system back pops the inner stack first.
- Since 3.38 the default Android page transition is `PredictiveBackPageTransitionsBuilder`.

## Deep links

- Declare the path patterns in the router; the same table serves `https://` App Links / Universal Links and custom schemes.
- Platform configuration (`AndroidManifest.xml` intent filters, `assetlinks.json`, associated domains entitlement, `apple-app-site-association`) is outside the widget layer. `flutter run` plus `adb shell am start -a android.intent.action.VIEW -d <url>` and `xcrun simctl openurl booted <url>` test it.
- A link that arrives before auth resolves must not bounce to the sign-in screen permanently: gate on a tri-state (`unknown` / `signedOut` / `signedIn`) and return `null` from `redirect` while unknown, showing a splash route.
- `onEnter` (go_router 16.3+) runs before the route is built and receives both the current and the next `GoRouterState` — use it for one-shot interception (consuming a referral link) and `redirect` for policy.
- `redirectLimit` (default 5) guards redirect loops; hitting it throws rather than hanging.

## State restoration

- `MaterialApp.restorationScopeId` plus `GoRouter(restorationScopeId: ...)` and a `restorationScopeId` on each `StatefulShellBranch` restores the navigation stack after the process is killed.
- Widget-level restoration uses `RestorationMixin` with `RestorableInt`/`RestorableString`/`RestorableTextEditingController` registered in `restoreState`.
- `state.extra` is not restorable without an `extraCodec`. Another reason to keep identity in the path.

Auth state, the `refreshListenable`, and the provider that exposes it belong to `riverpod-pro`; navigation assertions in tests belong to `flutter-testing-pro`.

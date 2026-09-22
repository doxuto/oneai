# Consumers and the widget boundary

Riverpod deliberately has no `context.watch`. A widget reaches providers through a `WidgetRef`,
which it gets by being a `ConsumerWidget`, a `ConsumerStatefulWidget`, or by wrapping a subtree in
a `Consumer`. Load this file when reviewing where `ref` comes from, how side effects reach the
UI, or how wide a rebuild is. Widget correctness itself — keys, layout, lifecycle, Material 3 —
belongs to `flutter-widgets-pro`.

## `ProviderScope`

```dart
void main() {
  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      observers: [LoggingObserver()],
      // retry: (count, error) => null,   // opt out of automatic retry app-wide
      child: const MyApp(),
    ),
  );
}
```

Exactly one `ProviderScope` at the root. `riverpod_lint`'s `missing_provider_scope` flags its
absence. Additional `ProviderScope`s deeper in the tree are for **scoping** only — they create a
child container and must declare `dependencies` on the providers they override; see
`architecture.md`. Wrapping a page in a bare `ProviderScope` to "isolate" it silently duplicates
every provider read below it.

## The three consumers

| | Use when |
|---|---|
| `ConsumerWidget` | The whole widget depends on providers and has no local state. |
| `ConsumerStatefulWidget` + `ConsumerState` | You need `initState`, `dispose`, an `AnimationController`, or a `TextEditingController`. |
| `Consumer` | Only a small part of an existing widget needs a provider, or you want to narrow the rebuild. |

```dart
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(userProvider);
    return Text(user.name);
  }
}
```

```dart
class EditorPage extends ConsumerStatefulWidget {
  const EditorPage({super.key});

  @override
  ConsumerState<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends ConsumerState<EditorPage> {
  late final TextEditingController _controller;
  late final ProviderSubscription<AsyncValue<Draft>> _sub;

  @override
  void initState() {
    super.initState();
    // `ref` is available in initState, but only ref.read / ref.listenManual.
    _controller = TextEditingController(text: ref.read(draftProvider).value?.body ?? '');
    _sub = ref.listenManual(draftProvider, (previous, next) { /* ... */ });
  }

  @override
  void dispose() {
    _sub.close();          // listenManual subscriptions are yours to close
    _controller.dispose();
    super.dispose();       // do not touch ref here — avoid_ref_inside_state_dispose
  }

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(draftProvider);
    return TextField(controller: _controller);
  }
}
```

`ConsumerState` exposes `ref` as a field, so `build` keeps the plain `(BuildContext context)`
signature. Using `ref.watch` in `initState` is an error; using `ref` at all in `dispose` is
flagged by `avoid_ref_inside_state_dispose` because the element is already deactivating.

## Narrowing rebuilds with `Consumer`

```dart
// Wrong: the whole page rebuilds when the badge count changes.
class HomePage extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadProvider);
    return Scaffold(
      appBar: AppBar(actions: [Badge(label: Text('$count'))]),
      body: const ExpensiveBody(),
    );
  }
}

// Right: only the badge rebuilds, and ExpensiveBody stays const.
class HomePage extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(actions: [
          Consumer(builder: (context, ref, _) =>
              Badge(label: Text('${ref.watch(unreadProvider)}'))),
        ]),
        body: const ExpensiveBody(),
      );
}
```

`Consumer`'s third builder argument is a `child` passed through unrebuilt — use it for an
expensive subtree that does not depend on the provider:

```dart
Consumer(
  child: const ExpensiveBody(),
  builder: (context, ref, child) =>
      Opacity(opacity: ref.watch(fadeProvider), child: child),
);
```

Combine with `select` (see `ref-lifecycle.md`) to narrow further: scope decides *which widgets*
rebuild, `select` decides *when*.

## Side effects belong in `ref.listen`

`build` must be free of side effects — it can run many times, and Riverpod may rebuild it while
the element tree is mid-update.

```dart
// Wrong: shows a dialog during build.
Widget build(BuildContext context, WidgetRef ref) {
  final state = ref.watch(loginProvider);
  if (state case AsyncError(:final error)) {
    showDialog(context: context, builder: (_) => ErrorDialog(error));   // throws
  }
  return const LoginForm();
}

// Right: listen registers the reaction, build stays pure.
Widget build(BuildContext context, WidgetRef ref) {
  ref.listen<AsyncValue<Session>>(loginProvider, (previous, next) {
    switch (next) {
      case AsyncError(:final error):
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(describe(error))));
      case AsyncData():
        Navigator.of(context).pushReplacementNamed('/home');
      case AsyncLoading():
        break;
    }
  });
  return const LoginForm();
}
```

Call `ref.listen` unconditionally at the top of `build`, exactly like a hook — never inside an
`if`, a loop, or a callback. `WidgetRef.listen` returns `void` and cleans itself up with the
element; `WidgetRef.listenManual` returns a `ProviderSubscription` you must close yourself.

Guard `context` use after an await inside the listener with `if (!context.mounted) return;`.

## Pull-to-refresh

```dart
RefreshIndicator(
  onRefresh: () => ref.refresh(articlesProvider.future),
  child: switch (ref.watch(articlesProvider)) {
    AsyncValue(:final value?) => ListView(children: [for (final a in value) ArticleTile(a)]),
    AsyncValue(:final error?) => ErrorList(error: error),
    _ => const Center(child: CircularProgressIndicator()),
  },
)
```

`ref.refresh(p.future)` returns a `Future` that completes when the new data lands (including
after any automatic retries), so the indicator spins for the right duration. `ref.refresh(p)`
returns the `AsyncValue` immediately and the indicator vanishes instantly — a common bug.

Both error and data branches must be scrollable, or `RefreshIndicator` has nothing to pull. Use
`ListView` with `physics: const AlwaysScrollableScrollPhysics()` for short content; the layout
details are `flutter-widgets-pro`'s.

## `hooks_riverpod`

`hooks_riverpod` adds `HookConsumerWidget` (with `build(BuildContext, WidgetRef)`) and
`HookConsumer`, letting `flutter_hooks` state and Riverpod providers coexist in one widget.

```dart
class SearchPage extends HookConsumerWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = useTextEditingController();   // disposed automatically
    final query = useState('');
    final results = ref.watch(searchProvider(query.value));
    return ...;
  }
}
```

It is worth adopting when the app has a lot of ephemeral widget state — controllers, tickers,
focus nodes — that would otherwise force `ConsumerStatefulWidget` everywhere. It is not worth
adopting for provider access alone: `hooks_riverpod` adds a second mental model and a second
package to keep in step. `hooks_riverpod` does not re-export `flutter_hooks`; declare both.

The legacy providers move too: with hooks the import is `package:hooks_riverpod/legacy.dart`.

## Review checklist

- Exactly one root `ProviderScope`; nested ones justified by scoping with `dependencies`.
- No `ref.watch` outside `build` / a provider body; no `ref.read` inside `build` except for
  `.notifier`.
- `ref.listen` called unconditionally, at the top of `build`.
- Dialogs, snackbars, navigation, haptics, analytics: in `listen`, not `build`.
- `listenManual` subscriptions closed in `dispose`; no `ref` use in `dispose`.
- Expensive subtrees kept `const` or passed as `Consumer`'s `child`.
- `ref.refresh(p.future)` — not `ref.refresh(p)` — behind a `RefreshIndicator`.

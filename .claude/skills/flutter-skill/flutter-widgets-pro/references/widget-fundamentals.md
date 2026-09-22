# Widget fundamentals

Read this before judging any widget structure question: whether something should be `const`, whether it needs a `Key`, whether a subtree belongs in a helper method or its own class, and why a rebuild is or is not expensive. Almost every "Flutter is slow" report is a violation of one of the rules here.

## Three trees

| Tree | Lifetime | What it is |
|---|---|---|
| `Widget` | One frame, usually | Immutable configuration. Cheap to allocate, thrown away constantly. |
| `Element` | As long as the widget stays in the same position with the same `runtimeType` and `key` | The mutable node. Holds `State`, the parent/child links, and the `InheritedWidget` dependency set. |
| `RenderObject` | Same as its element | Does layout, painting, hit testing. Expensive. |

`setState` marks an `Element` dirty. On the next frame the framework calls `build`, compares the new widget to the old one at each child position, and:

- same `runtimeType` and same `key` → the element is **updated in place**, `State` is kept, `didUpdateWidget` fires;
- different `runtimeType` or different `key` → the old element is **unmounted** (`dispose` runs) and a new one is inflated.

Everything about keys, `const`, and widget extraction follows from that comparison.

## `StatelessWidget` vs `StatefulWidget`

Use `StatefulWidget` only when the widget owns mutable state that must survive a rebuild: a controller, an animation, a subscription, a local toggle. Otherwise `StatelessWidget`.

```dart
class Badge extends StatelessWidget {
  const Badge({super.key, required this.count});
  final int count;

  @override
  Widget build(BuildContext context) => Text('$count');
}
```

Rules that fall out of immutability:

- All fields are `final`. A non-final field on a widget is a bug: the framework may reuse the element and never see the mutation.
- `State` fields are the mutable ones. Read the current configuration through `widget.x`, never through a copy taken in `initState` (it goes stale when the parent rebuilds with new values — see `state-lifecycle.md`).
- App-wide or screen-wide state does not belong in `State`. See `riverpod-pro`.

## `const` constructors

```dart
// Before — allocates a new SizedBox every frame and forces its subtree to update.
SizedBox(height: 16)

// After — canonicalised at compile time; identical on every rebuild.
const SizedBox(height: 16)
```

A `const` widget instance is canonicalised by the compiler, so the same object is returned every time. `Element.update` starts with `if (identical(newWidget, oldWidget)) return;` semantics via `Widget.canUpdate` plus an identity short-circuit, so a `const` child is skipped entirely when the parent rebuilds. This is the single highest-value, lowest-effort change in the widget layer.

To make it possible:

- Give every widget you write a `const` constructor and `final` fields.
- `const` propagates: a `const` parent requires `const` children, and once the outermost node is `const` the whole subtree is free.
- The `prefer_const_constructors` and `prefer_const_constructors_in_immutables` lints are in `flutter_lints`; leave them on. Lint configuration belongs to `dart-pro`.

What blocks `const`: anything read at runtime, including `Theme.of(context)`, a closure that captures a local, and a `Color` computed from a scheme. Move the runtime part outward and keep the leaves `const`.

## `build` purity

`build` may be called on any frame, many times, in any order relative to siblings. It must be a pure function of `widget`, `State` fields, and inherited widgets.

Never do in `build`:

| Wrong | Right |
|---|---|
| `TextEditingController()` / `AnimationController()` | create in `initState`, dispose in `dispose` |
| `http.get(...)`, `Firestore` reads | a provider (`riverpod-pro`) or `initState` |
| `setState(...)` | a callback, or `addPostFrameCallback` |
| `Navigator.push` / `showDialog` | an event handler or a post-frame callback |
| Mutating a `List` held in `State` | mutate inside `setState` |
| `DateTime.now()` used for animation | an `AnimationController` / `Ticker` |
| Sorting or filtering a large list | memoise in `State` / a provider |

## Keys — decision procedure

1. Is the widget the only child, or one of a fixed set of siblings that never reorder? **No key.** This is the common case.
2. Do siblings of the *same type* get inserted, removed, or reordered, and does any of them hold `State` (a controller, a checkbox, a scroll offset, an animation)? **`ValueKey<T>(model.id)`** — or `ObjectKey(model)` when the model has no stable id but its identity is stable.
3. Do you need to force a full teardown and rebuild of a subtree (reset an animation, drop a controller)? **`UniqueKey()`** — but a rebuilt-every-frame `UniqueKey` destroys state every frame, which is a common accidental bug.
4. Do you need to reach a widget's `State` from outside the tree, or move a subtree between parents? **`GlobalKey`**.

| Key | Equality by | Typical use |
|---|---|---|
| `ValueKey<T>` | `value == value` | List items keyed by id |
| `ObjectKey` | `identical(object, object)` | Items without an id but with a stable instance |
| `UniqueKey` | identity of the key itself | Forcing a rebuild-from-scratch |
| `PageStorageKey` | like `ValueKey`, plus scroll-offset persistence | Preserving scroll position of a list inside a `TabBarView` |
| `GlobalKey<T extends State>` | globally unique | `FormState`, `ScaffoldState`, branch `Navigator`s |

```dart
// Before — removing the first item makes every remaining tile adopt the
// previous tile's State: checkboxes and text fields shift by one.
for (final note in notes) NoteTile(note: note),

// After
for (final note in notes) NoteTile(key: ValueKey<String>(note.id), note: note),
```

`GlobalKey` costs: it is looked up in a global registry, it forces the element to be unmounted and remounted when it moves, and a duplicate global key is a hard error. Never generate one per list item, and never allocate one in `build` — store it in a `State` field.

## Helper method vs separate widget class

```dart
// Before — _buildHeader's subtree belongs to the caller's Element.
class ProfilePage extends StatelessWidget {
  Widget _buildHeader(BuildContext context) => Row(children: [...]);

  @override
  Widget build(BuildContext context) => Column(children: [_buildHeader(context), ...]);
}

// After
class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader();

  @override
  Widget build(BuildContext context) => const Row(children: [...]);
}
```

A separate class gets: its own `Element` (so it can be skipped when its inputs did not change), `const`-ability, its own entry in the widget inspector and rebuild counter, and its own dependency set for `Theme.of`/`MediaQuery.of`. A helper method gets none of those. Use a helper method only for a trivial, always-rebuilt fragment, or for a `Builder`-shaped callback.

`Builder` is the exception worth knowing: it exists purely to create a new `BuildContext` *below* a widget, which is how you read an `InheritedWidget` that the current `build` is itself installing (`Scaffold.of` inside the same `Scaffold`'s `body`, for example).

## `BuildContext` and inherited lookup

`BuildContext` *is* the `Element`. It describes a position in the tree, so:

- `Theme.of(context)` / `MediaQuery.of(context)` walk **up** from that position and register a dependency. When the inherited widget changes, every dependent element rebuilds.
- A `context` from an ancestor does not see descendants' inherited widgets. This is why `Scaffold.of(context)` inside the `Scaffold`'s own `build` fails and needs a `Builder`.
- `context.findAncestorStateOfType<T>()` and `findRenderObject()` are escape hatches: they do **not** create a dependency, they are O(depth), and they are invalid during `build` of an unmounted element. Prefer an `InheritedWidget`, a callback, or a provider.
- A stored `BuildContext` goes stale as soon as its element is unmounted. Do not cache one in a field; check `mounted` instead (`state-lifecycle.md`).

Custom `InheritedWidget` is still the right tool for pure, tree-scoped configuration that rarely changes (a theme extension, a scoped controller). For anything that changes often or has a lifecycle, use `riverpod-pro`.

## What belongs elsewhere

- Sealed classes, records, pattern matching in `build` → `dart-pro`.
- Providers, `ref.watch`, async state → `riverpod-pro`.
- `pumpWidget`, `find.byKey`, golden tests → `flutter-testing-pro`.

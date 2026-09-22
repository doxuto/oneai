# Collections and immutability

Dart's collection literals have grown a small language of their own — spreads, control flow, and null-aware elements — which removes almost every reason to build a list with a `for` loop and an `add`. The other half of this file is about not handing out a mutable reference to your own state, and about the two ways `Iterable` laziness will surprise you.

## Literal syntax

```dart
const empty = <String>[];                 // typed, const, canonical
final set = <int>{1, 2, 3};               // `{}` alone is a Map, not a Set
final map = <String, int>{'a': 1};
```

`{}` with no type argument and no context is a `Map<dynamic, dynamic>`. Write `<int>{}` for an empty set.

### Spread and null-aware spread

```dart
var a = [1, 2, null, 4];
var items = [0, ...a, 5];                 // [0, 1, 2, null, 4, 5]

List<int>? maybe = null;
var safe = [0, ...?maybe, 4];             // [0, 4] — `...?` inserts nothing for null
```

### Collection `if` and `for`

```dart
var includeItem = true;
var items = [0, if (includeItem) 1, 2, 3];

var numbers = [2, 3, 4];
var squares = [1, for (var n in numbers) n * n, 7];   // [1, 4, 9, 16, 7]

// `if-case` works here too
var parsed = [if (json case {'id': final String id}) id];
```

`if`/`for` elements are available in list, set, and map literals, and nest freely. They are the correct replacement for `..addAll`, `..add` inside a loop, and the ternary-with-empty-list trick.

### Null-aware elements (Dart 3.8)

```dart
int? absentValue = null;
int? presentValue = 3;
var items = [1, ?absentValue, ?presentValue, absentValue, 5]; // [1, 3, null, 5]
```

`?expr` evaluates `expr` and inserts it only if it is non-null — note the fourth element above, written without `?`, which inserts `null` normally. The same works for map keys and values:

```dart
var m = {
  'a': 1,
  ?maybeKey: 2,        // entry omitted entirely if maybeKey is null
  'c': ?maybeValue,    // entry omitted entirely if maybeValue is null
};
```

The key is evaluated before the value, and a null-aware key short-circuits the value. With `key: ?value` the key expression always runs, even when the value turns out to be null — keep side effects out of it.

```dart
// Before
final args = <String>[];
if (flag != null) args.add(flag);
if (name != null) args.add(name);

// After
final args = <String>[?flag, ?name];
```

## `const` collections

A `const` collection is canonicalised: every evaluation yields the same instance, and it is deeply immutable — `add` throws `UnsupportedError`.

```dart
const defaultTags = <String>['inbox', 'today'];
static const _codes = <int, String>{404: 'not found', 500: 'server error'};

class Note {
  const Note({this.tags = const <Tag>[]});  // const default for a collection field
  final List<Tag> tags;
}
```

- A `const` default argument value is the only way to give a collection parameter a shared, allocation-free default.
- `const` propagates: inside a `const` context the inner `const` keywords are implicit and `unnecessary_const` flags them. `prefer_const_literals_to_create_immutables` finds the ones you missed.
- `const` equality is identity-based canonicalisation: two `const ['a']` literals are `identical`; two non-const `['a']` literals are not equal at all.

## Unmodifiable views vs copies

| API | Copies? | Underlying changes visible? | Throws on mutate |
|---|---|---|---|
| `List.unmodifiable(xs)` | yes | no | yes |
| `UnmodifiableListView(xs)` | no (view) | **yes** | yes |
| `Map.unmodifiable(m)` | yes | no | yes |
| `UnmodifiableMapView(m)` | no (view) | **yes** | yes |
| `Set.unmodifiable(xs)` | yes | no | yes |
| `List.of(xs, growable: false)` | yes | no | on length change only |
| `xs.toList(growable: false)` | yes | no | on length change only |

The view classes (`UnmodifiableListView` is in `dart:collection`) are cheap but are still a window onto your mutable state. For a getter on a class whose internal list changes, a view is usually what you want — the caller cannot mutate, and does not get a stale snapshot. For something you hand across an isolate or store, copy.

```dart
import 'dart:collection';

class Repo {
  final List<Note> _notes = [];
  List<Note> get notes => _notes;                              // Before: callers can mutate
  late final List<Note> notes = UnmodifiableListView(_notes);  // After
}
```

`@immutable` from `package:meta` documents and lint-checks that all fields of a class are `final`; it does not make collections inside it immutable.

## `Iterable` laziness traps

`map`, `where`, `expand`, `whereType`, `take`, `skip`, `followedBy` and friends return a **lazy** `Iterable`. Nothing runs until it is iterated, and it re-runs on every iteration.

```dart
notes.map(save);                      // Trap 1: nothing is saved — map is lazy
for (final n in notes) save(n);       // do this instead

final expensive = notes.map(parse);   // Trap 2: the work runs twice
expensive.length;                     // parses everything
expensive.first;                      // parses again
notes.map(parse).toList(growable: false); // parse once

final view = notes.where((n) => n.pinned);  // Trap 3: view follows a mutable source
notes.clear();
view.length;                          // 0

for (final n in notes) {              // Trap 4: ConcurrentModificationError
  if (n.done) notes.remove(n);
}
notes.removeWhere((n) => n.done);     // correct
```

Rule: any `Iterable` that escapes the expression that created it gets a `.toList(growable: false)` or `.toSet()`. And `Iterable.map` with an `async` callback produces `Iterable<Future<T>>`, which nothing awaits — use `await Future.wait(xs.map(f))` for parallel, or a `for` loop with `await` inside for sequential.

## Equality of collections

`List`, `Set`, and `Map` use **identity** equality by default:

```dart
[1, 2] == [1, 2];          // false
const [1, 2] == const [1, 2]; // true — canonicalised const instances
{1, 2} == {1, 2};          // false
```

For value equality use `package:collection`:

```dart
import 'package:collection/collection.dart';

const ListEquality<int>().equals([1, 2], [1, 2]);         // true
const DeepCollectionEquality().equals({'a': [1]}, {'a': [1]}); // true
const UnorderedIterableEquality<int>().equals([1, 2], [2, 1]); // true
```

If a class has a collection field, its `==` **and** its `hashCode` must both use the same equality object:

```dart
@override
bool operator ==(Object other) =>
    other is Note && other.id == id && const ListEquality<Tag>().equals(other.tags, tags);

@override
int get hashCode => Object.hash(id, const ListEquality<Tag>().hash(tags));
```

Records are the exception: `(1, 'a') == (1, 'a')` is `true`, because records have structural equality. A record containing a `List` still compares that list by identity.

## `dart:core` vs `package:collection`

Already in `dart:core` — do not add a dependency for these:

| Member | Notes |
|---|---|
| `Iterable.nonNulls` | on `Iterable<T?>`, yields the non-null elements as `Iterable<T>` |
| `Iterable.indexed` | yields `(int index, T value)` records |
| `firstOrNull`, `lastOrNull`, `singleOrNull`, `elementAtOrNull(i)` | no `orElse` dance needed |
| `Iterable.whereType<T>()` | filters and narrows |
| `Object.hash`, `Object.hashAll`, `Object.hashAllUnordered` | |
| `List.generate`, `List.filled`, `List.of`, `List.from`, `List.unmodifiable` | |

Worth `package:collection` for:

| Member | Replaces |
|---|---|
| `firstWhereOrNull`, `lastWhereOrNull`, `singleWhereOrNull` | `firstWhere(..., orElse: () => null)` (which does not type-check under null safety) |
| `firstWhereIndexedOrNull`, `lastWhereIndexedOrNull` | manual index loops |
| `sortedBy`, `sortedByCompare`, `sorted` | `..sort()` on a copy |
| `groupListsBy`, `groupSetsBy`, `groupFoldBy` | manual `Map<K, List<V>>` accumulation |
| `ListEquality`, `MapEquality`, `SetEquality`, `DeepCollectionEquality` | hand-written comparisons |
| `equalsIgnoreAsciiCase`, `compareAsciiLowerCase` | locale-unsafe `toLowerCase()` comparisons |
| `PriorityQueue`, `QueueList`, `CanonicalizedMap`, `combinedListView` | hand-rolled structures |

`whereNotNull()` from `package:collection` is deprecated — use `dart:core`'s `nonNulls`.

Widget-level list handling (`ListView.builder`, keys, `itemCount`) is `flutter-widgets-pro`; Firestore collection decoding is `flutter-firebase-contract`.

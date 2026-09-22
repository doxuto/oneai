# Records and patterns

Records (Dart 3.0) give you anonymous, immutable, structurally typed aggregates. Patterns give you destructuring and exhaustiveness checking. Together they replace most of the `Tuple2` packages, most `Map<String, dynamic>` juggling, and most `if (x is A) ... else if (x is B)` chains. This file covers the syntax, the exhaustiveness rules, and the line between a record and a class.

## Record syntax

```dart
// Positional only
(int, String) pair = (1, 'one');
print(pair.$1);           // 1
print(pair.$2);           // 'one'

// Named only
({int id, String title}) row = (id: 1, title: 'One');
print(row.id);

// Mixed: positional fields are numbered $1..$n; named fields are not numbered
(int, String, {bool pinned}) mixed = (1, 'one', pinned: true);
print(mixed.$2);          // 'one'
print(mixed.pinned);      // true

// A one-positional-field record needs a trailing comma to disambiguate
(int,) single = (1,);
```

Facts that matter:

- Records are **immutable** and have **structural** `==` and `hashCode`. `(1, 'a') == (1, 'a')` is `true`. That makes them safe `Map` keys and safe `Set` members.
- Field names are part of the type: `({int id})` and `({int userId})` are different types.
- `$0` does not exist; positional fields start at `$1`.
- A record type is written exactly like a record value, in parentheses.
- Records cannot declare methods, cannot be subtyped, and cannot be `const` constructed with `const (...)` — but a record of constants is a constant if every field is.

## Records vs classes

| Use a record when | Use a class when |
|---|---|
| Returning 2–3 values from one function | The shape crosses a package or API boundary |
| The shape is used in one file and never named | The type has a name people say out loud |
| Field names are obvious from context | There is an invariant to enforce |
| No behaviour is attached | You need methods, `copyWith`, or subtypes |
| Structural equality is exactly what you want | Identity or custom equality matters |
| A local `for` loop needs a pair | It is serialised to/from JSON |

```dart
// Good: local, anonymous, two values
(Duration elapsed, int retries) timeCall(void Function() f) { /* ... */ }

// Bad: this is a domain type; name it
({String id, String title, String body, DateTime updatedAt}) fetchNote();
```

A `typedef` over a record buys a name but no invariants and no methods — acceptable for an internal cursor type, not for a domain entity.

## Destructuring

```dart
// Variable declaration
final (id, title) = ('n1', 'One');
final (:id, :title) = (id: 'n1', title: 'One');   // named shorthand

// Swap without a temporary (assignment pattern — no `final`/`var`)
(a, b) = (b, a);

// List and map patterns
final [first, second, ...rest] = <int>[1, 2, 3, 4];
final {'id': String id} = json;

// In a for-in loop
for (final (index, note) in notes.indexed) { /* ... */ }
for (final MapEntry(key: k, value: v) in map.entries) { /* ... */ }
```

`...rest` (the rest element) is valid only inside a list pattern, at most once. `...` on its own skips any number of elements without binding.

## Pattern kinds

| Kind | Syntax | Notes |
|---|---|---|
| Logical-or | `subpattern1 \|\| subpattern2` | Both sides must bind the same variables |
| Logical-and | `subpattern1 && subpattern2` | Commonly `>= 1 && <= 9` |
| Relational | `== e`, `!= e`, `< e`, `> e`, `<= e`, `>= e` | Against a constant expression |
| Cast | `foo as String` | Throws if it fails — use in irrefutable positions |
| Null-check | `subpattern?` | Matches if not null, then matches the subpattern against the non-null value |
| Null-assert | `subpattern!` | Throws on null; for irrefutable contexts |
| Constant | `123`, `null`, `'s'`, `math.pi`, `SomeClass.constant`, `const Thing(1, 2)`, `const (1 + 2)` | Compared with `==` |
| Variable | `var bar`, `String str`, `final int _` | Binds |
| Identifier | `foo`, `_` | Binds in a declaration; matches a constant in a matching context if capitalised as a constant |
| Parenthesized | `(subpattern)` | Grouping for `\|\|`/`&&` |
| List | `[a, b]`, `[a, ..., b]`, `[a, ...rest]` | Length is checked unless a rest element is present |
| Map | `{'key': a, someConst: b}` | Subset match — extra keys are allowed |
| Record | `(a, b)`, `(x: a, y: b)` | Shape must match exactly |
| Object | `SomeClass(x: a, y: b)`, `Loaded(:final value)` | Calls getters; `:final value` is shorthand for `value: final value` |
| Wildcard | `_`, `String _` | Matches anything, binds nothing |

The `:name` shorthand works in record, map-with-identifier, and object patterns and is the idiom you should use: `case Loaded(:final value)`.

## `switch` statements and expressions

```dart
// Expression form — every arm is an expression, arms separated by commas
final label = switch (state) {
  Loading() => 'Loading…',
  Loaded(value: []) => 'Empty',
  Loaded(:final value) => '${value.length} items',
  Failed(:final error) => 'Error: $error',
};

// Statement form — `case`, no fallthrough, `break` not required
switch (code) {
  case 200 || 201:
    handleOk();
  case >= 400 && < 500:
    handleClient();
  case final other:
    handleOther(other);
}
```

Rules:

- The expression form requires exhaustiveness. If the scrutinee is not exhaustively covered the analyzer reports an error; a `_ => ...` arm always completes it.
- The statement form warns rather than errors when non-exhaustive over a non-sealed type; over a `sealed` type or an `enum` it is an error.
- Guards use `when`: `case Loaded(:final value) when value.isNotEmpty:`. A guard failure moves on to the next case; it does not exit the switch.
- Do not add `default` (or `_`) to a switch over a `sealed` type or an enum. It defeats the entire purpose: adding a subtype should break the build.
- `unnecessary_breaks` flags the `break` that Dart 3 no longer needs.

## `if-case`

```dart
if (json case {'id': final String id, 'title': final String title}) {
  return Note(id: NoteId(id), title: title);
}

// With a guard
if (response case final http.Response r when r.statusCode == 200) {
  return r.body;
}

// else branch is allowed
if (state case Failed(:final error)) {
  report(error);
} else {
  proceed();
}
```

`if-case` is the correct replacement for `is` + cast, and for `map['k'] != null && map['k'] is String`.

## Exhaustiveness

Exhaustiveness is computed from the **static type** of the scrutinee:

| Scrutinee type | Exhaustive when |
|---|---|
| `sealed` class | every direct subtype in the declaring library is matched |
| `enum` | every value is matched |
| `bool` | `true` and `false` are matched |
| `bool?` | `true`, `false`, `null` |
| Nullable sealed `S?` | every subtype plus `null` |
| anything else | only with a wildcard or variable pattern |

A sealed hierarchy nests: matching an intermediate sealed subtype counts as covering its own subtypes only if that arm itself covers them.

```dart
sealed class Shape {}
sealed class Round extends Shape {}
final class Circle extends Round {}
final class Ellipse extends Round {}
final class Square extends Shape {}

double area(Shape s) => switch (s) {
  Round() => 0,          // covers Circle and Ellipse
  Square() => 1,
};
```

## Common pattern bugs

**`case 'a' | 'b':`** — the or-pattern operator is `||`, not `|`. `invalid_case_patterns` catches the Dart 2 style.

**`case Loaded(value)`** — object patterns match by **getter name**, not position. Write `Loaded(:final value)` or `Loaded(value: final v)`. Only record patterns are positional.

**`case [_, _]` on a `Set`** — list patterns work on `List` (and types with `length`/`[]` via `Iterable`? no). Match `Set` with an object pattern or convert to a list first.

**Map pattern assumed to check length** — `{'a': final x}` matches any map containing key `'a'`. There is no "exact keys" map pattern; check `map.length` in a guard if it matters.

**A guard that should be a pattern** — `case final n when n > 3:` is better written `case > 3:`; relational patterns participate in exhaustiveness reasoning, guards do not.

**Rebinding in `||`** — `case Circle(:final r) || Square(:final side):` is an error unless both sides bind identically named, identically typed variables.

Sealed hierarchy design and the class modifiers that enable exhaustiveness are in `classes-and-modifiers.md`.

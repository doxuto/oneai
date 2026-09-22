# The type system

Dart 3 has sound null safety: a non-nullable type is guaranteed non-null at run time, so the compiler removes the checks. Every escape hatch — `!`, `as`, `late`, `dynamic` — trades that guarantee for a run-time failure. This file is the rulebook for when an escape hatch is justified and what to write instead when it is not.

## Nullable vs non-nullable

| Declaration | Meaning | Default value |
|---|---|---|
| `String s` | never null; must be initialised before use | none — compile error if unset |
| `String? s` | may be null; must be narrowed before member access | `null` |
| `late String s` | non-null, initialised later; read-before-write throws | none |
| `late final String s` | non-null, assigned exactly once, lazily | none |
| `String s = 'x'` | non-null with an initialiser | `'x'` |
| `const String s = 'x'` | compile-time constant | `'x'` |

`late final T x = expr;` is different from `late final T x;` — the first is a lazily evaluated initialiser (evaluated on first read, memoised, useful for expensive singletons), the second is a write-once field.

## `late` — the decision procedure

1. Can the field be set in the constructor or from an initialiser? Then it is not `late`; set it.
2. Is `null` a meaningful value for this field ("no note selected")? Then it is `T?`, not `late`.
3. Is it genuinely initialised exactly once, before any read, in a lifecycle method (`initState`, an `init()` you control)? Then `late final T x;` is correct.
4. Is it expensive and possibly never needed? Then `late final T x = build();`.
5. Anything else — especially `late T x;` on a mutable field written from an async callback — is a `LateInitializationError` waiting to happen. Rewrite as `T?` plus promotion, or `T` with a sensible default.

```dart
// Before — throws LateInitializationError if the fetch fails or is slow
late List<Note> _notes;
Future<void> load() async => _notes = await api.fetch();

// After — the empty state is representable, so represent it
List<Note> _notes = const <Note>[];
Future<void> load() async => _notes = await api.fetch();
```

## Type promotion

Promotion narrows a variable's static type inside a region where the compiler can prove the narrowing holds.

```dart
void f(String? s) {
  if (s == null) return;
  print(s.length); // s promoted to String for the rest of the body
}
```

Promotion works on **local variables and parameters** that are not captured and reassigned by a closure. It works on **fields** only under the Dart 3.2 field-promotion rule.

### The private-final-field rule (Dart 3.2+)

A field promotes only if **all** of these hold:

| Requirement | Why |
|---|---|
| The field is private (`_name`) | A public field can be overridden by a getter in another library, which need not be stable. |
| The field is `final` | A non-final field can change between the test and the use. |
| The field is not `external` | External fields behave like external getters. |
| No getter with the same name exists elsewhere in the library | Any such getter could be unstable. |
| No non-promotable field with the same name exists elsewhere in the library | Same reason. |
| No class in the library gets an implicit `noSuchMethod` forwarder for that name | The forwarder is not stable. |

A private abstract getter declared in the same library can participate when every implementation of it in that library is itself a promotable private final field. If the analyzer refuses to promote and none of the reasons above look like the cause, run `dart analyze --verbose` — the diagnostic names the blocking declaration.

```dart
class Editor {
  Editor(this._draft);
  final Note? _draft;          // private + final → promotable

  String get title {
    if (_draft != null) return _draft.title; // OK in Dart 3.2+
    return 'Untitled';
  }
}

class BadEditor {
  BadEditor(this.draft);
  final Note? draft;           // public → NOT promotable

  String get title {
    if (draft != null) return draft.title; // error: use of nullable value
    return 'Untitled';
  }
}
```

When a field cannot be promoted, copy it to a local. Never reach for `!`:

```dart
// Before
if (widget.note != null) doSomething(widget.note!);

// After
final note = widget.note;
if (note != null) doSomething(note);
```

`this` never promotes. Assign it to a local first, or use a pattern: `if (this case final Loaded l)`.

## `dynamic` vs `Object?`

| | `dynamic` | `Object?` |
|---|---|---|
| Accepts any value | yes | yes |
| Member access unchecked at compile time | yes — typos compile | no — only `Object` members |
| Runtime failure mode | `NoSuchMethodError` at the call | none; you must narrow first |
| Triggers `avoid_dynamic_calls` | yes | no |

Use `Object?` for "I do not know the type yet". Use `dynamic` only where the API forces it (`jsonDecode` returns `dynamic`; assign it straight into an `Object?` local). Enable `strict-casts: true` so an implicit `dynamic → T` downcast becomes an error rather than a silent runtime check.

```dart
// Before
final data = jsonDecode(body);        // dynamic
final title = data['title'] as String; // TypeError at run time on bad input

// After
final Object? data = jsonDecode(body);
if (data case {'title': final String title}) { /* ... */ }
```

## Casting, `is`, and `as`

- `x is T` is a run-time test **and** promotes `x`.
- `x as T` is an unchecked assertion that throws `TypeError` on failure. Use it only when a failure genuinely means a programmer error.
- `x!` is `x as T` for the non-nullable `T`; it throws `TypeError` (`Null check operator used on a null value`).
- Generic types are checked at run time: `List<Object>` **is not** a `List<String>`, but `<String>[] is List<Object>` is `true` (covariance). A `List<dynamic>` from `jsonDecode` is not a `List<String>` — use `.cast<String>()` (lazy, throws on the offending element) or `List<String>.from(x)` (eager copy).
- `is` against an extension type tests the **representation type**. `NoteId('x') is String` is `true`. Extension types give no run-time identity.

```dart
// Before — one bad element throws far from the parse site
final tags = (json['tags'] as List).cast<String>();

// After — validated at the boundary
final raw = json['tags'];
final tags = raw is List ? raw.whereType<String>().toList(growable: false) : const <String>[];
```

## Generics and variance

Dart generics are **covariant** in their type argument: `List<Cat>` is a subtype of `List<Animal>`. This is unsound for writes, so Dart inserts a run-time check:

```dart
List<Animal> animals = <Cat>[];
animals.add(Dog()); // compiles; throws TypeError at run time
```

Prefer producing (`Iterable<T>` out) over consuming (`void add(T)`) on covariantly-used types. When you must accept a supertype-typed collection that you will write to, take `List<Object?>` or a generic method with its own parameter.

Bounds constrain, they do not vary:

```dart
T firstOr<T extends Object>(Iterable<T> xs, T fallback) =>
    xs.isEmpty ? fallback : xs.first;
```

`T extends Object` excludes nullable arguments; plain `<T>` has an implicit bound of `Object?`.

Enable `strict-raw-types: true` so `List` without a type argument is reported; a raw type silently becomes `List<dynamic>`.

## `covariant`

`covariant` on a parameter narrows an overridden method's parameter type and moves the check to run time. It is correct only when the class invariant guarantees the narrower type.

```dart
abstract class Shape {
  bool sameAs(Shape other);
}

class Circle extends Shape {
  Circle(this.radius);
  final double radius;

  // Without `covariant` this does not override Shape.sameAs.
  @override
  bool sameAs(covariant Circle other) => other.radius == radius;
}
```

Calling `Circle().sameAs(Square())` compiles through a `Shape` reference and throws `TypeError`. Prefer a `sealed` hierarchy and a `switch` over `covariant` whenever the set of subtypes is closed.

## Function types and typedefs

```dart
typedef NoteMapper = Note Function(Map<String, Object?> json);
typedef Json = Map<String, Object?>;            // non-function typedef
```

Function subtyping is contravariant in parameters and covariant in returns: `String Function(Object)` is a subtype of `Object Function(String)`. Do not annotate a callback parameter as `Function` — write the full function type so arity and types are checked.

Related: patterns and exhaustive switching live in `records-and-patterns.md`; the class-level modifiers that make a hierarchy closed live in `classes-and-modifiers.md`.

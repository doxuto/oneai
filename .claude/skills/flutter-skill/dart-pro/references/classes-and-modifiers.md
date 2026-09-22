# Classes, modifiers, and constructors

Dart 3 turned "what may other code do with this type?" into a declaration rather than a convention. Picking the right modifier is a design decision with compile-time consequences: `sealed` buys exhaustiveness, `final` buys the freedom to add members later without breaking downstream code, `base` buys the guarantee that your constructor always runs. This file is the capability matrix plus the constructor forms available in Dart 3.13.

## Modifier capability table

"Outside" means from a different library. Everything is permitted inside the declaring library unless stated.

| Modifier | Construct | Extend (outside) | Implement (outside) | Mix in | Exhaustive switch |
|---|---|---|---|---|---|
| *(none)* | yes | yes | yes | yes | no |
| `abstract` | no (anywhere) | yes | yes | yes | no |
| `base` | yes | yes — subtype must be `base`/`final`/`sealed` | **no** | **no** | no |
| `interface` | yes | **no** | yes | **no** | no |
| `final` | yes | **no** | **no** | **no** | no |
| `sealed` | **no** (implicitly abstract) | only in declaring library | only in declaring library | **no** | **yes** |
| `mixin` (declaration) | n/a | n/a (`on` clause instead) | yes | yes | no |
| `base mixin` | n/a | n/a | **no** | yes — implementer must be `base`/`final`/`sealed` | no |

Ordering when combining: `abstract` → one of `base`/`interface`/`final`/`sealed` → `mixin` → `class`. So `abstract base class`, `abstract interface class`, `base mixin class`. Forbidden: `abstract sealed` (sealed is already abstract) and `interface`/`final`/`sealed` before `mixin` (they forbid mixing in, which is a mixin's only purpose).

Transitivity: anything extending or implementing a `base` type must itself be `base`, `final`, or `sealed` — that is what propagates the "my constructor always runs" guarantee. `final` implies `base`, so in-library subtypes carry the same obligation. `sealed` subtypes are **not** implicitly abstract and are usually marked `final`.

### Which one to pick

| Intent | Declaration |
|---|---|
| Closed set of states/results | `sealed class` + `final class` subtypes |
| Value type nobody should subclass | `final class` |
| Published contract, implement-only | `abstract interface class` |
| Base class whose constructor must run | `base class` / `abstract base class` |
| Reusable behaviour across hierarchies | `mixin ... on Base` |
| Genuinely open for extension | plain `class` |

## Sealed hierarchies for state modelling

```dart
sealed class AuthState {
  const AuthState();
}

final class SignedOut extends AuthState {
  const SignedOut();
}

final class SigningIn extends AuthState {
  const SigningIn(this.email);
  final String email;
}

final class SignedIn extends AuthState {
  const SignedIn(this.uid, {this.isAnonymous = false});
  final String uid;
  final bool isAnonymous;
}

final class AuthFailure extends AuthState {
  const AuthFailure(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}
```

Rules that make this pay off:

- All subtypes in **one library** (one file, or a file with `part`s). `sealed` cannot span libraries.
- Every switch over `AuthState` omits `default`, so adding `SessionExpired` breaks compilation at every decision point — the whole point.
- Do not put a `bool isLoading` on the base class. If two states can coexist they are two fields, not a sealed hierarchy.
- Do not hand-write `when`/`map`/`maybeWhen`. Dart's `switch` expression is that method, and it is checked.

## Extension types (Dart 3.3)

An extension type is a compile-time-only view over a representation type. There is no wrapper object at run time.

```dart
extension type const NoteId(String value) {
  bool get isValid => value.isNotEmpty && !value.contains('/');
}

extension type Meters(double _v) implements num {
  Meters operator +(Meters other) => Meters(_v + other._v);
}
```

| Property | Behaviour |
|---|---|
| Run-time cost | none — erased to the representation type |
| Representation type's members | hidden unless you `implements` it |
| `is` / pattern matching | tests the **representation type**, not the extension type |
| Subtype safety | none at run time; a `String` reaches a `NoteId` parameter via any `dynamic` call |
| `const` constructor | allowed: `extension type const X(T v)` |
| Fields, `extends` | only the single representation field; no `extends` — `implements` instead |

Use an extension type when: you want a distinct static type over `String`/`int`/`Map<String, Object?>` with no allocation, and you control both ends. Use a real class when: you need run-time type identity, `==` that differs from the representation's, or subtyping.

```dart
void handle(Object o) { if (o is NoteId) {} }   // Wrong — true for ANY String

// Right — validate at the boundary, then rely on the static type
NoteId? parseId(Object? raw) =>
    raw is String && raw.isNotEmpty && !raw.contains('/') ? NoteId(raw) : null;
```

## Primary constructors (Dart 3.13)

```dart
class Point(var int x, var int y);   // `var`/`final` BEFORE the type

class const Size(final double w, final double h);  // const: no constructor body allowed

// Optional positional and named declaring parameters, with defaults and `required`
class Rect(final double left, {required final double width, final double height = 0});

class Point._(var int x, var int y);  // named primary constructor

// Initializer list / body goes in a `this` block inside the class body
class Temperature(final double celsius) {
  this : assert(celsius >= -273.15);

  double get fahrenheit => celsius * 9 / 5 + 32;
}
```

Constraints worth remembering:

- A declaring parameter with no `var`/`final` is a constructor parameter only — no field is created.
- Declaring parameters cannot be `late` or `external`, and are read-only inside the primary initializer scope. A `mixin class` may only have a parameterless primary constructor.
- `class const X(...)` may not have a `{ ... }` constructor body (same rule as any const constructor); an initializer list ending in `;` is fine.
- `extends`/`implements`/`with` clauses follow the parameter list: `class Employee(super.name, final String role) extends Person;`.
- Lints: `use_declaring_parameters`, `unnecessary_primary_constructor_body`, `unnecessary_type_name_in_constructor`, `initialize_in_field_declaration` (all new in 3.13).

Primary constructors are a readability win for small value types. They are not a reason to rewrite an existing class: one with a factory, a `copyWith`, and JSON methods reads no better in header form.

## Private named parameters (Dart 3.12)

```dart
class Note {
  const Note({required this._id, required this._title});
  final String _id;
  final String _title;
  String get id => _id;
}

const note = Note(id: 'n1', title: 'One'); // caller sees public names
```

The compiler strips the leading underscore for the caller. Neither the private name nor the generated public name may collide with another parameter, and this works only for initialising formals (`this._field`), not for ordinary named parameters.

## Constructor forms

| Form | Syntax | Use |
|---|---|---|
| Generative | `Note(this.id, this.title);` | the normal case |
| Named | `Note.empty() : id = '', title = '';` | alternative construction paths |
| Const | `const Note(this.id);` | all fields `final`, no body |
| Factory | `factory Note.fromJson(Map<String, Object?> j) => ...;` | may return a cached or subtype instance; has no `this` |
| Redirecting generative | `Note.untitled(String id) : this(id, 'Untitled');` | avoid duplicating an initializer list |
| Redirecting factory | `factory Note.of(String id) = _DefaultNote;` | dispatch to another class |
| Super parameter | `Child(super.id, {super.title})` | forward to the superclass; enable `use_super_parameters` |

Initializer lists run before the body and before the superclass constructor's body; `assert`s there are the cheapest invariant checks you will ever write, and they are stripped in release mode.

## `copyWith`, equality, and `hashCode`

```dart
final class Note {
  const Note({required this.id, required this.title, this.body = ''});

  final String id;
  final String title;
  final String body;

  Note copyWith({String? title, String? body}) =>
      Note(id: id, title: title ?? this.title, body: body ?? this.body);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Note && other.id == id && other.title == title && other.body == body;

  @override
  int get hashCode => Object.hash(id, title, body);
}
```

Rules:

- `==` and `hashCode` are overridden together, always (`hash_and_equals`), and never on a mutable class (`avoid_equals_and_hash_code_on_mutable_classes`).
- `Object.hash(a, b, c)` for up to 20 fields; `Object.hashAll(iterable)` for a collection; `Object.hashAllUnordered` for sets. Do not hand-roll `a.hashCode ^ b.hashCode` — XOR collides on swapped fields.
- A `List`/`Map`/`Set` field is compared by identity unless you use `ListEquality`/`DeepCollectionEquality` from `package:collection` in both `==` and `hashCode`.
- The `copyWith` above cannot set a nullable field back to `null`. If that matters, use a sentinel (`Object? title = _unset`) or generate the class.

## When to generate instead

| Signal | Tool |
|---|---|
| More than ~4 fields with `==`, `hashCode`, `copyWith`, `toString`; or a `copyWith` that can null a field | `package:freezed` |
| Sealed union with JSON discriminators | `package:freezed` + `json_serializable` |
| Only `==`/`hashCode` needed | `package:equatable` |
| JSON only | `package:json_serializable` |

Generated code arrives via `part 'note.freezed.dart';` / `part 'note.g.dart';` — see `style-and-lints.md` for the `part`/`part of` and analyzer-exclusion rules. Widget-level immutability (`const` widgets, `Key`) belongs to `flutter-widgets-pro`.

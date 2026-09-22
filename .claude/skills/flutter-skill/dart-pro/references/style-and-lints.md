# Style, lints, and layout

The analyzer is a first-class part of the language: `analysis_options.yaml` decides how much of Dart's type system is actually enforced and which of the ~200 lint rules run. A project that ships with only `flutter_lints` and no `analyzer.language` block is running with several checks switched off. This file is the configuration you should expect to find, and what to add when it is missing.

## `analysis_options.yaml`

```yaml
include: package:flutter_lints/flutter.yaml
# or, for a stricter house style:
# include: package:very_good_analysis/analysis_options.yaml

analyzer:
  language:
    strict-casts: true       # no implicit dynamic → T downcasts
    strict-inference: true   # no silently-inferred dynamic
    strict-raw-types: true   # no bare `List`, `Future`, `Map`
  errors:
    invalid_annotation_target: ignore   # freezed/json_serializable noise
    todo: ignore
    unawaited_futures: error            # promote a lint so CI fails on it
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "**/*.mocks.dart"
    - "build/**"

linter:
  rules:
    # correctness
    - avoid_dynamic_calls
    - avoid_slow_async_io
    - cancel_subscriptions
    - close_sinks
    - collection_methods_unrelated_type
    - unrelated_type_equality_checks
    - hash_and_equals
    - avoid_equals_and_hash_code_on_mutable_classes
    - only_throw_errors
    - throw_in_finally
    - avoid_catches_without_on_clauses
    - discarded_futures
    - unawaited_futures
    - test_types_in_equals
    - invalid_case_patterns
    - implicit_call_tearoffs

    # style / intent
    - always_declare_return_types
    - prefer_final_locals
    - prefer_final_in_for_each
    - prefer_const_constructors
    - prefer_const_constructors_in_immutables
    - prefer_const_declarations
    - prefer_const_literals_to_create_immutables
    - use_super_parameters
    - use_enums
    - unnecessary_breaks
    - unnecessary_underscores
    - sort_constructors_first
    - directives_ordering
    - avoid_positional_boolean_parameters
    - library_private_types_in_public_api
    - always_use_package_imports
    - avoid_print

    # Dart 3.13
    - use_declaring_parameters
    - unnecessary_primary_constructor_body
    - unnecessary_type_name_in_constructor
    - unnecessary_const_in_enum_constructor
    - initialize_in_field_declaration
    - empty_container_bodies
```

Notes on that file:

- `include` takes one package. `flutter_lints` 6.0.0 (min Dart 3.8) builds on `package:lints`' `recommended.yaml`. `very_good_analysis` 11.x is much stricter and already enables most of the list above; with it, the `linter.rules` block shrinks to the handful you want to *disable*.
- A rule listed under `linter.rules` is enabled; to disable one that the included set turns on, use the map form: `prefer_double_quotes: false`.
- `analyzer.errors` maps a **diagnostic name** (not only lints) to `ignore`/`info`/`warning`/`error`. Promoting a lint to `error` makes CI fail on it.
- `exclude` removes files from analysis entirely. Generated files belong there; your own code never does. Suppressing a single line is `// ignore: rule_name`, a whole file `// ignore_for_file: rule_name` — every such comment should say why on the same line.
- `strict-casts` is the single highest-value switch in the file: it turns every implicit `dynamic` downcast (the entire `jsonDecode` surface) into a compile error.

## Rules worth arguing about

| Rule | Why it is contentious | Recommendation |
|---|---|---|
| `require_trailing_commas` | The Dart 3.7+ tall formatter no longer needs trailing commas to keep things split | Leave off; let the formatter decide |
| `always_specify_types` | Fights `var`/`final` inference and bloats code | Off. Use `strict-raw-types` instead |
| `omit_local_variable_types` | The inverse of the above | On if the team wants terse locals |
| `public_member_api_docs` | Essential in a package, noise in an app | On for `packages/`, off for `lib/` of an app |
| `avoid_catches_without_on_clauses` | Legitimate at top-level boundaries | On, with targeted `// ignore:` at the two or three real boundaries |
| `prefer_relative_imports` vs `always_use_package_imports` | Mutually exclusive | Pick one and enforce it; `package:` imports survive file moves better |
| `discarded_futures` | Very noisy on event handlers | On, paired with disciplined `unawaited()` |
| `specify_nonobvious_property_types` | New and opinionated | Optional |

`use_build_context_synchronously` is a widget-layer rule; it belongs in the same file but the rationale is `flutter-widgets-pro`'s.

## `dart format`

- Run `dart format .` in CI with `--set-exit-if-changed`. There is no configuration beyond `--line-length` (default 80); do not argue about it.
- Dart 3.7 introduced the "tall" style, and Dart 3.8 made the formatter add and remove trailing commas intelligently. Dart 3.13 added a blank line between import sections and changed method-chain splitting. The style is **language-versioned**: the formatter reads the pubspec's SDK lower bound, so a package on `sdk: ^3.6.0` still gets the old style. Bump the constraint if the diff surprises you.
- Never hand-format around the formatter. If a line formats badly, extract a local variable or a helper.
- `// dart format off` / `// dart format on` exists for data tables; use it rarely.

## Naming

| Kind | Convention | Example |
|---|---|---|
| Class, enum, extension, extension type, typedef, mixin | `UpperCamelCase` | `NoteRepository`, `NoteId` |
| Library, package, directory, file | `lowercase_with_underscores` | `note_repository.dart` |
| Variable, parameter, function, method, named constructor | `lowerCamelCase` | `updatedAt`, `Note.fromJson` |
| Constant | `lowerCamelCase` (not `SCREAMING_CAPS`) | `defaultPageSize` |
| Private | leading `_` | `_controller` |
| Unused binding | `_` (a true wildcard since Dart 3.7) | `(_, final v)` |

Further: acronyms longer than two letters are capitalised as words (`HttpClient`, not `HTTPClient`); a two-letter acronym stays uppercase (`ID` → but `id` as a variable); boolean names read as predicates (`isEmpty`, `hasListener`, `canRetry`); do not prefix getters with `get`.

## File and library layout

```
lib/
  main.dart
  src/                       # everything not exported
    domain/note.dart
    data/note_repository.dart
    ui/notes_page.dart
  notes.dart                 # public barrel, `export 'src/domain/note.dart';`
```

- One primary public class per file, named after the file.
- Order inside a file: imports (`dart:`, then `package:`, then relative — `directives_ordering` enforces it, and 3.13's formatter puts a blank line between the groups), then `part` directives, then public declarations, then private ones.
- Order inside a class: static constants, instance fields, constructors (`sort_constructors_first`), public methods, private methods, `@override`s grouped with the interface they implement.
- For a package, everything real lives under `lib/src/` and only barrels sit at `lib/`. Enforce with `implementation_imports` in consumers.

## `part` / `part of`

`part` exists for exactly one thing in modern Dart: generated code.

```dart
// note.dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'note.freezed.dart';
part 'note.g.dart';
```

Rules:

- The generated file declares `part of 'note.dart';` — the **string URI** form, not `part of some.library.name`. Enable `use_string_in_part_of_directives`.
- Parts share the library's private scope; that is the whole point for generators, and the reason not to use `part` to split hand-written code. Split by creating another library and importing it.
- `library;` with no name is the modern form when you need a library-level annotation or doc comment (`unnecessary_library_name` flags the named form).
- Add `*.g.dart` / `*.freezed.dart` to `analyzer.exclude`, not to `.gitignore`, unless the team regenerates on every build.

## Doc comments

```dart
/// Loads the notes for [uid], newest first.
///
/// Emits [Loading] immediately, then either [Loaded] or [Failed].
/// Throws nothing: transport failures arrive as a [Failed] state.
///
/// ```dart
/// final repo = NoteRepository(source)..start();
/// ```
Stream<LoadState<List<Note>>> watch(String uid) { /* ... */ }
```

- `///`, never `/** */`.
- First sentence is a noun phrase for a getter/variable, a verb phrase for a function, on one line, ending in a period.
- `[Identifier]` links; enable `comment_references` so a renamed symbol breaks the link visibly.
- Document what is *not* obvious: ownership, nullability rationale, whether it throws, whether the returned `Iterable` is lazy, who must call `dispose`.
- Do not document `@override`s that add nothing; the base doc is inherited.

Riverpod-specific analyzer setup (`custom_lint`, `riverpod_lint`) is `riverpod-pro`; test-only lints and CI wiring are `flutter-testing-pro`.

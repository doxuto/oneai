---
name: dart-pro
description: Writes, reviews, and refactors Dart 3.13 language code inside Flutter applications — types, null safety, records, patterns, sealed classes, class modifiers, extension types, async and error modelling. Use when reading, writing, or reviewing code that uses sealed, base, interface, final, mixin, extension type, records, switch expressions, if-case, late, covariant, Future, Stream, StreamController, Completer, Isolate.run, or analysis_options.yaml, or when the user mentions null safety, type promotion, pattern matching, copyWith, immutability, lints, or dart format.
license: MIT
metadata:
  author: doxuto
  version: "1.0"
  targets: "Dart 3.13.4, Flutter 3.47.5, flutter_lints 6.0.0, very_good_analysis 11.x"
---

Write and review the Dart language half of a Flutter codebase: type modelling, null safety, patterns, class design, asynchrony, error handling, and analyzer configuration. Report only genuine problems — do not nitpick or invent issues.

## Core principles

1. **The type system is the specification; `dynamic` and `late` are admissions of defeat.** A nullable type says "this can legitimately be absent". `late` says "I know something the compiler does not" and converts a compile error into a `LateInitializationError` at runtime. Prefer `T?` with a promotion site, or restructure so the field is set in the constructor.
2. **Model alternatives as `sealed` hierarchies, not as a bag of nullable fields.** `sealed class` + `switch` gives compile-time exhaustiveness; a class with `T? data; Object? error; bool loading` gives eight states of which five are nonsense. Sealed subtypes must live in the same library as the base.
3. **Records are for anonymous, local, structural tuples. Everything with a name, an invariant, or a lifetime is a class.** `(int, int)` for a two-value return is right; `(String, String, bool, DateTime)` crossing three files is not.
4. **Immutability by default.** `final` fields, `const` constructors, `const` literals, `List.unmodifiable` at API boundaries. A `const` constructor is the only way a widget subtree can be skipped during rebuild — see `flutter-widgets-pro`.
5. **Every `Future` is awaited, returned, or explicitly `unawaited`; every `StreamSubscription` is cancelled and every `StreamController` closed.** Unhandled async errors in Dart do not crash the isolate helpfully — they reach `PlatformDispatcher.instance.onError` or vanish into a zone.
6. **Errors are values at the boundary and exceptions in the middle.** Throw for programmer errors and unexpected failures; return a `sealed` result only where the caller must branch on every failure mode. Never `catch (e)` with an empty or log-only body.
7. **The analyzer runs before you do.** A review that reports something `analysis_options.yaml` would catch is a review that should have started by fixing `analysis_options.yaml`.

## Review process

1. Check null safety, `late`, type promotion, casts, generics, and `dynamic` leaks using `references/type-system.md`.
2. Check records, destructuring, `switch` expressions, `if-case`, and exhaustiveness using `references/records-and-patterns.md`.
3. Check class modifiers, sealed state hierarchies, extension types, constructors, equality, and `copyWith` using `references/classes-and-modifiers.md`.
4. Check `Future`/`Stream` usage, subscriptions, controllers, scheduling, and isolates using `references/async.md`.
5. Check throw/catch shape, `rethrow`, async error propagation, and framework error handoff using `references/errors.md`.
6. Check collection literals, `const` collections, laziness, and equality using `references/collections-and-immutability.md`.
7. Check `analysis_options.yaml`, lint selection, formatting, naming, and library layout using `references/style-and-lints.md`.
8. Flag any removed, renamed, or hallucinated API using `references/common-mistakes.md`.

If doing a partial review, load only the relevant reference files.

## Core instructions

- Target Dart `sdk: ^3.13.0` with `flutter: ">=3.47.0"`. Do not use a language feature older than the pubspec's lower bound allows, and do not use one newer than 3.13 (`class Point(var int x)` primary constructors are 3.13; private named parameters are 3.12; dot shorthands are 3.10; null-aware elements `?expr` are 3.8; wildcards `_` are 3.7; extension types are 3.3).
- Flag every `late` that exists only to avoid `?`. `late final` set exactly once in `initState`/an init method is acceptable; `late` on a mutable field that some code path reads before writing is a latent `LateInitializationError`.
- Never write `!` on a value the compiler could have promoted. `if (x != null) { x.foo(); }` promotes; `x!.foo()` does not. A field only promotes when it is **private and final** and no other declaration in the library shadows promotability — copy it to a local first: `final v = _value; if (v != null) ...`.
- Reject `as` casts that are not guarded by an `is` check or a pattern. `value as String` on a `dynamic` from JSON throws `TypeError` at the cast site with no useful context; `if (value case final String s)` does not.
- Never type a parameter or variable `dynamic` to silence the analyzer. Use `Object?` — it is just as permissive at the call site and forbids method calls until you narrow. `dynamic` disables every check including typo detection.
- Use `sealed` for closed hierarchies, `final` for leaf types that must not be subclassed, `base` when subclasses must exist but the implementation contract must hold, `interface` for contracts you publish but do not want extended. Plain `class` is the default only for types genuinely open to extension.
- Switch over a `sealed` supertype with no `default` clause. The `default` re-opens the switch and silently swallows the new subtype you add next month; omit it and the analyzer reports every non-exhaustive switch.
- Prefer a `switch` expression over a chain of `if (x is A)`. Use object patterns to destructure in the same step: `case Loaded(:final value)`.
- Give every value type `const` constructors, `final` fields, `operator ==`, and `hashCode`. If the class has more than about four fields or needs deep collection equality, stop hand-writing them and use `package:freezed` or `package:equatable` — hand-written `hashCode` over five fields is where bugs hide. `Object.hash(a, b, c)` and `Object.hashAll(list)` are the correct primitives.
- Do not put `operator ==` on a mutable class (`avoid_equals_and_hash_code_on_mutable_classes`): a mutated key silently disappears from a `Set` or `Map`.
- `await` every `Future` or mark it `unawaited(...)` from `dart:async` with a comment saying why. Turn on `unawaited_futures` and `discarded_futures`. A dropped future's error is reported as an uncaught async error, not at the call site.
- `Future.wait` rejects with the **first** error but still waits for every future by default; `eagerError: true` makes it reject as soon as one fails while the rest keep running. Neither cancels anything — a `Future` in Dart is not cancellable.
- Close what you open. A `StreamController` that is never `close()`d leaks its subscribers; a `StreamSubscription` that is never `cancel()`ed keeps its callback and everything it captures alive. Enable `cancel_subscriptions` and `close_sinks`.
- Catch narrowly: `on FormatException catch (e)`, `on TimeoutException`. A bare `catch (e)` must either `rethrow` or convert to a domain error and record `e` **with its `StackTrace`** — `catch (e, st)`. Never `catch (_) {}`.
- `print` is banned in shipped code (`avoid_print`). Use `debugPrint` for throttled console output in debug builds, or `dart:developer`'s `log(message, name:, error:, stackTrace:, level:)` for anything structured.
- Use `const` on every literal and constructor invocation that can be `const`, and prefer `const` collections for static tables. Enable `prefer_const_constructors`, `prefer_const_literals_to_create_immutables`, and `prefer_const_declarations`.
- Reach for `package:collection` (`firstWhereOrNull`, `groupListsBy`, `sortedBy`, `ListEquality`, `DeepCollectionEquality`) before writing a manual loop or a `firstWhere(orElse: ...)` dance. `Iterable.nonNulls`, `.indexed`, `.elementAtOrNull` and `.whereType<T>()` are in `dart:core` already.
- Keep state management out of this layer. Notifier shape, provider lifecycle, and `AsyncValue` belong to `riverpod-pro`; `BuildContext` and rebuild semantics belong to `flutter-widgets-pro`.

## Canonical example

`lib/domain/note.dart`:

```dart
/// Zero-cost wrapper: compiles away to `String` at run time (Dart 3.3+).
extension type const NoteId(String value) {
  bool get isValid => value.isNotEmpty && !value.contains('/');
}

/// Primary constructor (Dart 3.13). `final` on a declaring parameter
/// creates the field; `class const` makes the generated constructor const.
class const Tag(final String label, {final bool pinned = false}) {
  @override
  bool operator ==(Object other) =>
      other is Tag && other.label == label && other.pinned == pinned;

  @override
  int get hashCode => Object.hash(label, pinned);

  @override
  String toString() => 'Tag($label, pinned: $pinned)';
}

class Note {
  const Note({
    required this.id,
    required this.title,
    this.body = '',
    this.tags = const <Tag>[],
    this.updatedAt,
  });

  final NoteId id;
  final String title;
  final String body;
  final List<Tag> tags;
  final DateTime? updatedAt;

  Note copyWith({String? title, String? body, List<Tag>? tags}) => Note(
    id: id,
    title: title ?? this.title,
    body: body ?? this.body,
    tags: tags ?? this.tags,
    updatedAt: updatedAt,
  );

  /// Parses untrusted JSON. Every field is pattern-matched, never cast.
  /// A map pattern requires the key to be PRESENT, so optional fields
  /// get their own `if-case` rather than a nullable subpattern.
  static Note? tryParse(Object? json) {
    if (json case {'id': final String id, 'title': final String title}
        when id.isNotEmpty) {
      var body = '';
      if (json case {'body': final String b}) body = b;
      return Note(id: NoteId(id), title: title, body: body);
    }
    return null;
  }
}

/// Closed set of outcomes. No `default` anywhere it is switched over.
sealed class LoadState<T> {
  const LoadState();
}

final class Loading<T> extends LoadState<T> {
  const Loading();
}

final class Loaded<T> extends LoadState<T> {
  const Loaded(this.value);
  final T value;
}

final class Failed<T> extends LoadState<T> {
  const Failed(this.error, this.stackTrace);
  final Object error;
  final StackTrace stackTrace;
}

/// Exhaustive switch expression — adding a subtype breaks compilation here.
String describe(LoadState<List<Note>> state) => switch (state) {
  Loading<List<Note>>() => 'Loading…',
  Loaded<List<Note>>(value: []) => 'No notes yet',
  Loaded<List<Note>>(:final value) => '${value.length} notes',
  Failed<List<Note>>(:final error) => 'Failed: $error',
};
```

`lib/data/note_repository.dart`:

```dart
import 'dart:async';

import 'package:collection/collection.dart';

import '../domain/note.dart';

class NoteRepository {
  NoteRepository(this._source);

  final Stream<List<Note>> _source;

  final _controller = StreamController<LoadState<List<Note>>>.broadcast();
  StreamSubscription<List<Note>>? _subscription;

  Stream<LoadState<List<Note>>> get states => _controller.stream;

  Future<void> start() async {
    await _subscription?.cancel();   // never drop the cancel future
    _controller.add(const Loading());
    _subscription = _source.listen(
      (notes) => _controller.add(Loaded(notes)),
      onError: (Object error, StackTrace stackTrace) =>
          _controller.add(Failed(error, stackTrace)),
      cancelOnError: false,
    );
  }

  /// Returns a record: two values, used only here, so no class is warranted.
  (Note? newest, int total) summarise(List<Note> notes) {
    final newest = notes
        .sortedBy<DateTime>((n) => n.updatedAt ?? DateTime(0))
        .lastOrNull;
    return (newest, notes.length);
  }

  Note? find(List<Note> notes, NoteId id) =>
      notes.firstWhereOrNull((n) => n.id == id);

  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    await _controller.close();
  }
}
```

Rendering `LoadState` into a widget tree is `flutter-widgets-pro`; exposing it as provider state is `riverpod-pro`.

## Output format

If the user asks for a review, organize findings by file. For each issue:

1. State the file and relevant line(s).
2. Name the rule being violated.
3. Show a brief before/after code fix.

Skip files with no issues. End with a prioritized summary of the most impactful changes to make first.

If the user asks you to write or improve code, follow the same rules but make the changes directly instead of returning a findings report.

Example output:

### lib/data/note_repository.dart

**Line 41: `StreamSubscription` stored but never cancelled in `dispose` — the callback and everything it captures outlive the repository (`cancel_subscriptions`).**

```dart
// Before
Future<void> dispose() async {
  await _controller.close();
}

// After
Future<void> dispose() async {
  await _subscription?.cancel();
  _subscription = null;
  await _controller.close();
}
```

**Line 12: `late` used to dodge nullability on a field written from an async callback — throws `LateInitializationError` if `states` is read before `start()` completes.**

```dart
// Before
late List<Note> _cache;

// After
List<Note> _cache = const <Note>[];
```

### Summary

1. **Leak (high):** The subscription on line 41 keeps the source stream and its listener alive for the process lifetime.
2. **Crash (high):** `late` on line 12 turns an ordering bug into a runtime error with no recovery path; a `const []` default removes the failure mode entirely.

End of example.

## References

- `references/type-system.md` — sound null safety, `late` and `LateInitializationError`, nullable vs non-nullable, type promotion and the Dart 3.2 private-final-field rule, `covariant`, generics and variance, `dynamic` vs `Object?`, `is`/`as`/`!` pitfalls, `strict-casts` and `strict-raw-types`.
- `references/records-and-patterns.md` — record syntax, positional and named fields, `$1`/`$2`, destructuring, `switch` expressions, `if-case`, `for-in` patterns, exhaustiveness, the full pattern-kind table, records vs classes.
- `references/classes-and-modifiers.md` — `sealed`/`final`/`base`/`interface`/`mixin`/`abstract` capability table, sealed state hierarchies, `extension type` and when it is zero cost, primary constructors (3.13), private named parameters (3.12), `const` constructors, `copyWith`, `operator ==`/`hashCode`, when to switch to `freezed`.
- `references/async.md` — `Future` combinators and `Future.wait` error behaviour, `Stream`, `async*`, `await for`, `Completer`, `unawaited`, subscriptions and cancellation, broadcast vs single-subscription, `StreamController` hygiene, microtask vs event queue, `Timer`, `scheduleMicrotask`, `Zone`, `Isolate.run` and `compute`.
- `references/errors.md` — `Exception` vs `Error`, throwing vs sealed `Result`, `on`/`catch`/`finally`, `rethrow` and stack traces, errors across async gaps, `runZonedGuarded`, `FlutterError.onError`, `PlatformDispatcher.instance.onError`, never swallowing `Object`.
- `references/collections-and-immutability.md` — `const` collections, spread and `...?`, collection-`if`/`for`, null-aware elements (3.8), `List.unmodifiable` and `UnmodifiableListView`, `Iterable` laziness traps, collection equality, `package:collection` and `package:meta`.
- `references/style-and-lints.md` — `analysis_options.yaml` skeleton, `flutter_lints` vs `very_good_analysis`, `strict-casts`/`strict-inference`/`strict-raw-types`, lints worth enabling beyond the defaults, `dart format` tall style and trailing commas, naming, `part`/`part of` for generated code, doc comments.
- `references/common-mistakes.md` — removed, renamed, and hallucinated Dart APIs with the correct replacement: `dart:html` vs `package:web`, `new`, `List()`, `describeEnum`, `firstWhere(orElse: () => null)`, `whenComplete` vs `finally`, `late` misuse, `print`, `whereNotNull`, `dart:isolate` misuse.

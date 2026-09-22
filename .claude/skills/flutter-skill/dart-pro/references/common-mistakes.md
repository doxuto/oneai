# Common mistakes and hallucinated APIs

Every entry: what is written, why it is wrong, what to write instead. When reviewing, quote the line and point at the entry. When writing, if an identifier is not on this page or in the bundle's fact sheet and you are not certain it exists, write "verify against the Dart API docs" next to it rather than guessing.

## Removed, renamed, or deprecated

**`new Note('x')` / `new List()`**
`new` has been optional since Dart 2 and is flagged by `unnecessary_new`. Write `Note('x')`.

**`List()` / `new List(5)` / `List(growable: false)`**
The unnamed `List` constructor was removed in Dart 2.9 and does not exist under null safety. Use `<T>[]`, `List<T>.filled(5, value)`, `List<T>.generate(5, (i) => ...)`, `List<T>.empty(growable: true)`, or `List<T>.of(other)`.

**`import 'dart:html';`**
Deprecated and unsupported when compiling to Wasm. `package:web` (built on `dart:js_interop`) replaces `dart:html`, `dart:svg`, `dart:web_audio`, `dart:web_gl`, and `dart:indexed_db`; `dart:js_interop` / `dart:js_interop_unsafe` replace `dart:js` and `dart:js_util`. In a Flutter app, prefer `package:web` behind a conditional import rather than touching either from shared code.

**`describeEnum(MyEnum.value)`**
Deprecated in `package:flutter/foundation.dart` (after v3.14.0-2.0.pre). Dart 3 enums have `.name` from `dart:core`'s `EnumName` extension: `MyEnum.value.name`. To go the other way use `MyEnum.values.byName('value')` or `MyEnum.values.firstWhereOrNull((e) => e.name == s)` for a non-throwing lookup.

**`xs.firstWhere((x) => p(x), orElse: () => null)`**
Does not compile under null safety when `xs` is `Iterable<T>` with non-nullable `T`, because `orElse` must return `T`. Use `firstWhereOrNull` from `package:collection`.

**`xs.whereNotNull()`**
Deprecated in `package:collection`. Use `dart:core`'s `xs.nonNulls`.

**`xs.firstOrNull` "does not exist, add package:collection"**
It does exist in `dart:core` (`IterableExtensions`), along with `lastOrNull`, `singleOrNull`, `elementAtOrNull`, and `indexed`. Do not add a dependency for them.

**`Tuple2<int, String>` / `package:tuple`**
Superseded by records: `(int, String)`. Do not add the dependency to new code.

**`class Foo with Bar` where `Bar` is a plain class**
Dart 3 forbids using a class as a mixin unless it is declared `mixin class`. Declare `mixin Bar` (or `mixin class Bar` if it must also be instantiable).

**`part of my.library.name;`**
The dotted form is legacy. Use `part of 'note.dart';` (`use_string_in_part_of_directives`).

**`library my_package.note;`**
Named libraries are legacy; write bare `library;` only when you need a library-level annotation or doc (`unnecessary_library_name`).

**`import 'package:flutter/material.dart' show describeIdentity;`** and similar
`describeIdentity`, `shortHash`, `objectRuntimeType` live in `package:flutter/foundation.dart`, not `material.dart`.

**`dart:ffi`'s `Pointer.asFunction` without `isLeaf`/`@Native`** and other FFI details
Out of scope for this skill; verify against the current `dart:ffi` docs before asserting anything.

## Null safety misuse

**`late` used to dodge nullability**

```dart
// Before
late String _token;              // LateInitializationError on any early read
Future<void> init() async => _token = await fetchToken();

// After
String? _token;
Future<void> init() async => _token = await fetchToken();
String get token => _token ?? (throw StateError('init() not awaited'));
```

`late` is for a value that is genuinely assigned before any read, or for a lazy initialiser `late final x = expensive()`. It is not a nullability escape hatch.

**`value!` after a null check on a field**
The `!` compiles, but so does removing it if the field is private and final (Dart 3.2 field promotion). When it is not promotable, copy to a local: `final v = _value; if (v != null) ...`. A codebase full of `!` is a codebase that has stopped getting any benefit from null safety.

**`x ??= await compute()` in a getter**
`??=` on a `Future`-returning call inside a synchronous getter does not compile; and as a memoisation idiom it races. Use `late final Future<T> x = compute();`.

**`if (list?.isNotEmpty)`**
`bool?` is not a `bool`. Write `if (list?.isNotEmpty ?? false)` or `if (list != null && list.isNotEmpty)`.

**`String? s; s.length`** after `s = 'x'` inside a closure
Assignment inside a closure defeats promotion. Use a local, or a `final`.

## Async mistakes

**`whenComplete` used as `catch`**
`whenComplete` is `finally`, not `catch`: it runs on both paths and does not consume the error. Use `try`/`catch`/`finally` in an `async` function.

**`try { doAsync(); } catch (e) {}` with no `await`**
An `async` function returns a failed future rather than throwing, so nothing is caught and the error escapes to the zone. `await` it.

**`stream.listen(...)` wrapped in `try`/`catch`**
Stream errors never reach that `catch`. Pass `onError: (Object e, StackTrace st) => ...` to `listen`, or use `await for` inside the `try`.

**`onError: (e) => ...`**
Drops the stack trace. Use `(Object e, StackTrace st)`.

**`Future.wait` assumed to cancel the rest on failure**
It does not. Nothing in Dart cancels a `Future`. `eagerError: true` only makes the *combined* future complete sooner; the individual futures run to completion. Use `cleanUp:` to release what the winners produced.

**`f.timeout(d)` assumed to cancel `f`**
It does not. The original future still runs and still reports its result or error (to the zone, unhandled).

**`Future.delayed` used for something that must be cancellable**
Use `Timer`, which has `cancel()`.

**`await for` over a broadcast app-event stream inside a method the caller awaits**
Never returns. Use `listen` plus a stored subscription.

**`compute(_parse, bytes)` with a non-top-level callback**
`compute` and `Isolate.spawn` require a top-level or static function (`Isolate.run` takes a closure, but the closure must not capture non-sendable state). A method tear-off or a closure over `this` fails at run time.

**`Isolate.run(() => context.read(...))`** or any closure capturing a `BuildContext`, plugin channel, or open socket
Not sendable. Pass plain data in, return plain data out.

**`StreamController` never closed / `StreamSubscription` never cancelled**
The two most common leaks in a Flutter app. Enable `close_sinks` and `cancel_subscriptions`; cancel the subscription before closing the controller.

**`controller.add(x)` after `close()`**
Throws `StateError`. Guard with `if (!controller.isClosed)` when a producer can outlive disposal.

**`scheduleMicrotask` used to "defer to the next frame"**
Microtasks run *before* the event queue, so this defers nothing and can starve the frame pipeline. Use `Future<void>.delayed(Duration.zero)`, or `WidgetsBinding.instance.addPostFrameCallback` for a frame boundary (that one is `flutter-widgets-pro`'s).

## Pattern and class mistakes

**`case 'a' | 'b':`**
The or-pattern operator is `||`. `invalid_case_patterns` flags the Dart 2 form.

**`case Loaded(value):`**
Object patterns match by getter name, not position. Write `Loaded(:final value)`.

**`default:` on a switch over a `sealed` type or an enum**
Removes the exhaustiveness check, which was the reason for `sealed`. Delete it.

**`sealed` subtypes in another file without `part`**
Sealed subtypes must be in the same **library**. Put them in one file, or make the extra files `part`s of it.

**`abstract sealed class`**
Compile error — `sealed` is already implicitly abstract.

**`final mixin` / `interface mixin` / `sealed mixin`**
Compile errors: those modifiers forbid mixing in. Only `base` may precede `mixin`.

**`extension type` treated as a real type at run time**
`is`, `as`, and patterns see the representation type. `NoteId('x') is String` is `true`, and a `String` can arrive at a `NoteId` parameter through `dynamic`. Validate at the boundary.

**`extension` used where `extension type` was meant (or the reverse)**
`extension Foo on String {}` adds static members to an existing type and keeps the type. `extension type Foo(String s) {}` creates a new static type. They are different features with similar names.

**`a.hashCode ^ b.hashCode`**
Collides on swapped fields and on equal values. Use `Object.hash(a, b)` / `Object.hashAll(list)`.

**`operator ==` without `hashCode`** (or the reverse)
`hash_and_equals`. A `Set` or `Map` will behave incorrectly.

**`copyWith` that cannot set a field to `null`**
`title: title ?? this.title` makes `copyWith(title: null)` a no-op. If the field is nullable and must be clearable, generate the class or use an explicit sentinel.

## Logging and diagnostics

**`print('...')` in shipped code**
Unthrottled, present in release builds, truncated by the Android log buffer. `avoid_print`. Use `debugPrint` for console output in debug builds, or `dart:developer`'s `log(message, name:, error:, stackTrace:, level:)` for anything structured.

**`debugPrint` assumed to be stripped in release**
It is not; it is throttled, and it still runs. Guard with `if (kDebugMode)` or route through your own logger.

**`assert` used for input validation**
Assertions are removed in release builds. Validate with a real check and an `ArgumentError`/`FormatException`.

**`toString()` relied upon for parsing**
`toString` output is not a contract and is minified/obfuscated in release. Serialise explicitly.

## Version-gating mistakes

| Feature | Minimum SDK | Do not use below |
|---|---|---|
| records, patterns, class modifiers, switch expressions, `if-case` | 3.0 | — |
| private final field promotion | 3.2 | write an explicit local |
| `extension type` | 3.3 | use a wrapper class |
| digit separators (`1_000_000`) | 3.6 | write the plain literal |
| wildcard `_` as a true non-binding name | 3.7 | name it `_unused` |
| null-aware elements (`?expr`) | 3.8 | use collection-`if` |
| dot shorthands (`.running`) | 3.10 | write the type name |
| private named parameters (`this._x`) | 3.12 | take a public parameter and assign |
| primary constructors (`class P(var int x)`) | 3.13 | write a normal constructor |

Check the package's `environment: sdk:` constraint before using any of these; the analyzer reports a language-version error, but only if the constraint is honest.

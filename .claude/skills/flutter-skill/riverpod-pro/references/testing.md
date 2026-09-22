# Testing providers

Riverpod's testability comes from one fact: every provider can be overridden. A test replaces the
leaves of the graph — repositories, clients, clocks — and exercises the real providers above them.
Load this file for provider-level tests. The widget-test mechanics around them — `pumpWidget`,
`pump` vs `pumpAndSettle`, finders, golden files — belong to `flutter-testing-pro`.

## `ProviderContainer.test()`

New in 3.0 and the default entry point. It creates a container and registers its disposal with
`addTearDown`, so tests no longer hand-roll a `createContainer` helper.

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('greeting is built from the locale', () {
    final container = ProviderContainer.test(
      overrides: [localeProvider.overrideWithValue(const Locale('fr'))],
    );

    expect(container.read(greetingProvider), 'Bonjour');
  });
}
```

| Member | Use |
|---|---|
| `container.read(p)` | Current value. Reading an auto-dispose provider does not keep it alive. |
| `container.listen(p, cb, {fireImmediately})` | Subscribe **and** keep the provider alive for the test. |
| `container.refresh(p)` / `container.invalidate(p)` | Force recomputation. |
| `container.exists(p)` | Whether the provider was ever initialised. |
| `container.pump()` | Await pending rebuilds and listener notifications. |
| `container.updateOverrides([...])` | Swap overrides mid-test. |
| `container.dispose()` | Automatic with `.test()`. |

Use `container.listen` rather than `container.read` whenever the provider is auto-dispose and the
test spans more than one statement — otherwise it may be destroyed between assertions.

```dart
test('counter increments', () {
  final container = ProviderContainer.test();
  final sub = container.listen(counterProvider, (_, __) {});

  expect(sub.read(), 0);
  container.read(counterProvider.notifier).increment();
  expect(sub.read(), 1);
});
```

## Choosing an override

| Method | Available on | Replaces | Use for |
|---|---|---|---|
| `p.overrideWithValue(v)` | `Provider`, and async providers (with an `AsyncValue`) | the whole state | injecting a fake repository or a fixed value |
| `p.overrideWith(create)` | all | the body | a fake that still needs `ref` |
| `p.overrideWith(Fake.new)` | notifier providers | the notifier class | replacing behaviour wholesale |
| `p.overrideWithBuild(cb)` | notifier providers | only `build()` | keeping the real methods, faking the initial state |

```dart
// 1. A concrete value.
todoRepositoryProvider.overrideWithValue(FakeTodoRepository()),

// 2. A body that still reads other providers.
articlesProvider.overrideWith((ref) async => [Article(id: ref.watch(seedProvider))]),

// 3. A whole fake notifier. It must EXTEND the real one, not implement it.
todoListProvider.overrideWith(FakeTodoList.new),

// 4. Only the initial state; real methods keep working.
todoListProvider.overrideWithBuild((ref, self) => [const Todo(id: '1', title: 'seed')]),
```

`overrideWithBuild` is new in 3.0 and is usually what you want when testing a notifier's methods:
you skip the network in `build()` without losing the logic under test. Its signature is
`Override overrideWithBuild(RunNotifierBuild<NotifierT, ValueT> build)`; the callback receives the
`Ref` and the notifier instance and returns the initial value.

Mocks of a `Notifier` must **extend** it (`class Fake extends TodoList`), because Riverpod reads
the generated element type. `class Fake implements TodoList` fails at runtime. Better still,
avoid mocking notifiers: fake the repository underneath and let the real notifier run.

### Family overrides

```dart
// One argument
userProvider('u-1').overrideWithValue(const AsyncValue.data(alice)),

// Every argument — note: `family.overrideWith` was deprecated in 3.2.0 in favour of
// `family.overrideWith2`; check which one the pinned version exposes.
userProvider.overrideWith2((ref, id) async => User(id: id, name: 'Test $id')),
```

## Async providers

Read `.future` and await it. It resolves past loading *and past the automatic retries*.

```dart
test('articles load', () async {
  final container = ProviderContainer.test(
    overrides: [apiProvider.overrideWithValue(FakeApi(articles: [a1, a2]))],
  );

  await expectLater(container.read(articlesProvider.future), completion([a1, a2]));
  expect(container.read(articlesProvider), isA<AsyncData<List<Article>>>());
});
```

A test for the **failure** path must disable retry, or it waits for ten backoff intervals
(~38 s) before the future completes:

```dart
final container = ProviderContainer.test(
  retry: (retryCount, error) => null,
  overrides: [apiProvider.overrideWithValue(FailingApi())],
);

await expectLater(
  container.read(articlesProvider.future),
  throwsA(isA<SocketException>()),
);
```

This is the single most common cause of "my Riverpod test hangs" in 3.x.

## Testing a notifier without a widget tree

```dart
test('toggle flips the todo and rolls back on failure', () async {
  final repository = FakeTodoRepository(todos: [const Todo(id: '1', title: 'a', done: false)]);
  final container = ProviderContainer.test(
    retry: (_, __) => null,
    overrides: [todoRepositoryProvider.overrideWithValue(repository)],
  );
  final sub = container.listen(todoListProvider, (_, __) {});

  await container.read(todoListProvider.future);

  repository.failNextWrite = true;
  await container.read(todoListProvider.notifier).toggle('1');
  await container.pump();

  expect(sub.read().requireValue.single.done, isFalse); // rolled back
});
```

Rules:

- Always `await` the initial `.future` before calling a method that itself awaits `future`.
- `await container.pump()` after an action, to flush rebuilds before asserting.
- Assert on `AsyncValue` subclasses (`isA<AsyncError<T>>()`), not on `.value!`.
- Record the sequence when order matters: pass a real callback to `container.listen` and collect
  `(previous, next)` pairs.

## Widget tests: `tester.container`

`RiverpodWidgetTesterX` adds `container` to `WidgetTester`, replacing the Riverpod 2 dance of
`ProviderScope.containerOf(tester.element(find.byType(...)))`.

```dart
testWidgets('shows the seeded todo', (tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [todoRepositoryProvider.overrideWithValue(FakeTodoRepository())],
      child: const MaterialApp(home: TodoListPage()),
    ),
  );
  await tester.pumpAndSettle();

  expect(tester.container().read(todoListProvider), isA<AsyncData<List<Todo>>>());
  expect(find.text('Buy milk'), findsOneWidget);
});
```

Every widget test that touches providers needs a `ProviderScope` in the pumped tree, and every
injection-point provider (the ones whose bodies throw `UnimplementedError`) must be overridden or
the test fails with that exception. That failure is the design working: it is impossible to
accidentally hit the network from a test.

## Faking the leaves

```dart
class FakeTodoRepository implements TodoRepository {
  FakeTodoRepository({List<Todo> todos = const []}) : _todos = [...todos];
  final List<Todo> _todos;
  bool failNextWrite = false;

  @override
  Future<List<Todo>> fetchAll() async => List.unmodifiable(_todos);

  @override
  Future<void> setDone(String id, {required bool done}) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw const SocketException('offline');
    }
    final i = _todos.indexWhere((t) => t.id == id);
    _todos[i] = _todos[i].copyWith(done: done);
  }
}
```

Hand-written fakes beat `mockito` here: the interface is small, the fake is readable, and it can
model real behaviour (ordering, failure injection) that a stub cannot. Reach for a mock only to
assert that a call happened.

## Observers in tests

`ProviderObserver` is useful for asserting the shape of a state sequence. Its Riverpod 3 callbacks
take a single `ProviderObserverContext` rather than separate `provider`/`container` parameters —
a Riverpod 2 observer will not compile. Pass observers via `ProviderContainer.test(observers: [...])`
or `ProviderScope(observers: [...])`.

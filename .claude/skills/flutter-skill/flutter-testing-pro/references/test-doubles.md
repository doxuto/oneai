# Fakes, mocks, and substituting the outside world

Read this when a test needs to stand in for a repository, an HTTP client, a plugin, or a platform channel. The default answer is a hand-written fake behind an interface you own. Package versions below were checked on pub.dev on 2026-09-22.

## The hierarchy of test doubles

| Double | What it is | When |
|---|---|---|
| **Fake** | A working implementation with a simplified backing store | Default. Repositories, data sources, caches, clocks |
| **Stub** | Returns canned values, no logic | A one-line fake; the distinction rarely matters in Dart |
| **Mock** | Records calls so the test can assert on them | Only when the *call itself* is the behaviour under test |
| **Spy** | Real object with recorded calls | Rare in Dart; a fake with a counter is simpler |
| **`Fake` (the class)** | `flutter_test`'s base class that throws on any un-overridden member | Implementing a wide interface where you only care about three members |

## Hand-written fakes

```dart
// lib/features/todos/data/todo_repository.dart — the interface YOU own
abstract interface class TodoRepository {
  Future<List<Todo>> fetchAll();
  Future<void> setDone(String id, {required bool done});
  Stream<List<Todo>> watchAll();
}
```

```dart
// test/support/fake_todo_repository.dart
class FakeTodoRepository implements TodoRepository {
  FakeTodoRepository({List<Todo> todos = const []}) : _todos = [...todos];

  final List<Todo> _todos;
  final _controller = StreamController<List<Todo>>.broadcast();

  // Observable state the test asserts on, instead of verify() calls.
  int fetchCount = 0;
  final List<(String id, bool done)> writes = [];
  Object? failNextWith;

  Object? _takeFailure() {
    final e = failNextWith;
    failNextWith = null;
    return e;
  }

  @override
  Future<List<Todo>> fetchAll() async {
    fetchCount++;
    if (_takeFailure() case final Object e) throw e;
    return List.unmodifiable(_todos);
  }

  @override
  Future<void> setDone(String id, {required bool done}) async {
    if (_takeFailure() case final Object e) throw e;
    writes.add((id, done));
    final i = _todos.indexWhere((t) => t.id == id);
    _todos[i] = _todos[i].copyWith(done: done);
    _controller.add(List.unmodifiable(_todos));
  }

  @override
  Stream<List<Todo>> watchAll() => _controller.stream;
}
```

Why this is the default:

- It compiles against the real interface. Add a method and the fake fails to compile — a generated mock silently returns `null`.
- `fetchCount` and `writes` give the test the same information `verify()` would, in a form that reads as a value assertion.
- No code generation, no `build_runner` step, no `.mocks.dart` churn in diffs.
- It is readable as documentation of what the interface is supposed to do.

`implements` (not `extends`) is correct here: you want the compiler to demand every member.

## `Fake` from `flutter_test`

For a wide interface where three members matter, `Fake` throws `UnimplementedError` on everything you have not overridden, which turns an unexpected call into a clear failure rather than a null.

```dart
import 'package:flutter_test/flutter_test.dart';

class FakeNavigatorObserver extends Fake implements NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}
```

`Fake` is exported by `flutter_test` and by `package:test`.

## `mocktail` versus `mockito`

| | `mocktail` 1.0.5 | `mockito` 5.8.1 |
|---|---|---|
| Code generation | none | `build_runner` + `@GenerateNiceMocks` |
| Null safety of arguments | `registerFallbackValue` for non-primitive `any()` | handled by the generator |
| Stubbing syntax | `when(() => mock.f()).thenAnswer(...)` — note the closure | `when(mock.f()).thenAnswer(...)` |
| Generated file in the diff | no | `*.mocks.dart` |
| Maintained by | felangel (Very Good Ventures) | the Dart team |

Both are fine. Pick one per repository. Reach for either only when you need something a fake cannot express cheaply:

- asserting a call did **not** happen (`verifyNever`)
- asserting call **order** (`verifyInOrder`)
- asserting on arguments that are awkward to record by hand
- standing in for a class with dozens of members where writing a fake is genuinely disproportionate

```dart
// mocktail
import 'package:mocktail/mocktail.dart';

class MockAnalytics extends Mock implements Analytics {}

void main() {
  setUpAll(() {
    // Required before any() / captureAny() of a non-primitive type.
    registerFallbackValue(const AnalyticsEvent.unknown());
  });

  test('checkout logs purchase exactly once', () async {
    final analytics = MockAnalytics();
    when(() => analytics.log(any())).thenAnswer((_) async {});

    await Checkout(analytics: analytics).complete();

    verify(() => analytics.log(const AnalyticsEvent.purchase())).called(1);
    verifyNever(() => analytics.log(const AnalyticsEvent.purchaseFailed()));
  });
}
```

The `mockito` equivalent declares `@GenerateNiceMocks([MockSpec<Analytics>()])`, imports the generated `checkout_test.mocks.dart`, and drops the closures: `verify(analytics.log(...)).called(1)`.

`@GenerateNiceMocks` is the recommended `mockito` API: un-stubbed members return a legal default instead of throwing. `@GenerateMocks` throws, which is occasionally what you want and usually just noise. Run `dart run build_runner build --delete-conflicting-outputs` after changing annotations; by default only annotations in files under `test/` are processed.

## Do not mock what you do not own

```dart
// Before — encodes your guess about Firestore's behaviour, and breaks on SDK updates
class MockFirestore extends Mock implements FirebaseFirestore {}
when(() => firestore.collection(any())).thenReturn(mockCollection);
when(() => mockCollection.doc(any())).thenReturn(mockDoc);
when(() => mockDoc.get()).thenAnswer((_) async => mockSnapshot);
// ... six more lines before a single assertion

// After — one interface you own, one fake, one assertion
abstract interface class TodoRemoteSource {
  Future<List<TodoDto>> fetchAll(String uid);
}

class FakeTodoRemoteSource implements TodoRemoteSource {
  FakeTodoRemoteSource(this.todos);
  final List<TodoDto> todos;
  @override
  Future<List<TodoDto>> fetchAll(String uid) async => todos;
}
```

The thin `FirestoreTodoRemoteSource` adapter is then covered once by an integration test or the emulator suite, instead of by a mock cathedral in every unit test. The Flutter-side shape of that boundary is owned by `flutter-firebase-contract`.

## HTTP

Use `MockClient` from `package:http/testing.dart`. It is a real `http.BaseClient` with a handler function — not a mock object.

```dart
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

test('parses the todo list', () async {
  final client = MockClient((request) async {
    expect(request.url.path, '/v1/todos');
    expect(request.headers['authorization'], 'Bearer t0ken');
    return http.Response('{"items":[{"id":"1","title":"a","done":false}]}', 200,
        headers: {'content-type': 'application/json'});
  });

  final repository = HttpTodoRepository(client: client, token: 't0ken');

  expect(await repository.fetchAll(), hasLength(1));
});

test('maps a 401 to SessionExpired', () async {
  final client = MockClient((_) async => http.Response('', 401));
  final repository = HttpTodoRepository(client: client, token: 'stale');

  await expectLater(repository.fetchAll(), throwsA(isA<SessionExpired>()));
});
```

`MockClient.streaming(handler)` takes a `StreamedRequest` and returns a `StreamedResponse`, for download progress and server-sent events. For `dio`, substitute the `HttpClientAdapter`; do not mock `Dio` itself.

Widget tests already install an `HttpOverrides` that answers every request with a 400, so a stray `NetworkImage` renders an error rather than reaching the network. Plain `test` bodies do not get that protection — set `HttpOverrides.global` in `test/flutter_test_config.dart` (its entry point is `Future<void> testExecutable(FutureOr<void> Function() testMain)`, and it runs before every test file in the package).

## Platform channels

Plugins talk over `MethodChannel`. Replace the platform side with `TestDefaultBinaryMessengerBinding`.

```dart
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() {
    messenger.setMockMethodCallHandler(channel, (call) async => switch (call.method) {
      'getApplicationDocumentsDirectory' => '/tmp/test-docs',
      _ => null,
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
  });
}
```

| Method on `TestDefaultBinaryMessenger` | Signature |
|---|---|
| `setMockMethodCallHandler` | `void setMockMethodCallHandler(MethodChannel channel, Future<Object?>? Function(MethodCall message)? handler)` |
| `setMockDecodedMessageHandler` | `void setMockDecodedMessageHandler<T>(BasicMessageChannel<T> channel, Future<T> Function(T? message)? handler)` |
| `setMockMessageHandler` | `void setMockMessageHandler(String channel, MessageHandler? handler, [Object? identity])` |
| `setMockStreamHandler` | `void setMockStreamHandler(EventChannel channel, MockStreamHandler? handler)` |
| `checkMockMessageHandler` | `bool checkMockMessageHandler(String channel, Object? handler)` |
| `allMessagesHandler` | property: intercept every outgoing message on every channel |

Passing `null` as the handler removes it — do this in `addTearDown`, or the handler leaks into the next test file that shares the binding.

The removed form is `channel.setMockMethodCallHandler(...)` directly on the `MethodChannel`; see `common-mistakes.md`.

Many federated plugins expose a platform-interface class instead, which is cleaner than channel mocking when available — assign your fake to the `…Platform.instance` setter.

## `SharedPreferences`

```dart
// Legacy SharedPreferences API.
setUp(() => SharedPreferences.setMockInitialValues({'seenOnboarding': true}));

// SharedPreferencesAsync / SharedPreferencesWithCache — install the in-memory
// platform implementation from shared_preferences_platform_interface instead.
setUp(() {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData({'seenOnboarding': true});
});
```

`static void setMockInitialValues(Map<String, Object> values)` is annotated `@visibleForTesting`, nullifies any existing singleton, and prefixes keys automatically. `InMemorySharedPreferencesAsync.empty()` and `.withData(Map<String, Object> data)` are its two constructors.

## Asserting on a fake instead of verifying on a mock

```dart
// Before — passes even if the app saved the wrong todo
verify(() => repository.setDone(any(), done: any(named: 'done'))).called(1);

// After — says what actually happened
expect(repository.writes, [('1', true)]);
```

The second form fails with `Expected: [('1', true)] Actual: [('2', true)]`, which names the bug. The first form fails with a call-count mismatch, which does not.

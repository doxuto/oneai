# What to test, and what not to

Read this before writing a new suite, when a coverage number is being argued about, or when a test is expensive and nobody can say what it protects. The question is never "is this tested" but "is this tested by the cheapest kind of test that can catch its bugs".

## The decision table

| Code kind | Test kind | Entry point | Assert on |
|---|---|---|---|
| Pure function, extension, formatter | unit | `test` | return value, thrown error |
| Model / `copyWith` / `==` / JSON | unit | `test` | round-trip equality, malformed input |
| Error mapping (`FirebaseException` → domain error) | unit | `test` | the mapped type, not the message string |
| Repository / API client | unit with a fake transport | `test` + `MockClient` | parsed result, error classification, retry counts |
| `Notifier` / `AsyncNotifier` | provider test, no widget tree | `ProviderContainer.test()` | sequence of `AsyncValue`s — owned by `riverpod-pro` → `references/testing.md` |
| Single widget with visible states | widget | `testWidgets` | rendered text, presence/absence, semantics |
| Page wired to providers | widget with overrides | `testWidgets` + `ProviderScope` | what the user sees per state |
| Navigation between two pages | widget | `testWidgets` with a real `Navigator` | the destination is on screen |
| Pixel-exact appearance of a reusable component | golden | `expectLater(..., matchesGoldenFile(...))` | the image, once, per platform |
| Sign-up → onboarding → home, on a device | integration | `integration_test` | the flow completes; a handful of checkpoints |
| Frame timings for a scroll | integration + trace | `traceAction` / `watchPerformance` | summarised timings, not per-frame values |

## The pyramid as it actually applies to Flutter

The classic pyramid assumes widget-level tests are expensive. In Flutter they are not: a `testWidgets` body runs in-process, in fake time, in roughly the time of a unit test. The practical shape is:

```
        integration_test          few, slow, device-bound, high value per test
      ────────────────────
     golden tests                 few, brittle across machines, pin visual contracts
   ────────────────────────
  widget tests                    MANY — this is where Flutter apps actually get value
────────────────────────────
unit tests                        many, instant, for everything with no BuildContext
```

The inversion that matters: most Flutter bugs are *rendering and state-wiring* bugs, which unit tests structurally cannot see and integration tests see too late. Budget accordingly — a healthy Flutter repository has more `testWidgets` than `test`.

## What not to test

| Do not test | Why | Instead |
|---|---|---|
| Framework widgets (`Column` lays out children, `Text` shows text) | You are testing Flutter | Test *your* composition of them |
| Generated code (`*.g.dart`, `*.freezed.dart`) | You are testing the generator | Test the hand-written code that calls it |
| Private methods via `@visibleForTesting` | Couples the test to the arrangement | Drive them through the public entry point |
| Exact widget tree shape (`find.byType(Padding)` counts) | Breaks on every refactor | Assert on text, keys, semantics |
| A mock's own behaviour (`verify(mock.x()).called(1)` as the only assertion) | Tautology: the mock does what you told it | Assert on the observable outcome |
| `build()` returning a specific widget type | Implementation detail | Assert what is rendered |
| Log output, analytics calls, `debugPrint` | Not behaviour a user depends on | Skip, unless the event *is* the product |
| Third-party SDK internals (Firestore query building) | Not yours, and the fake is a guess | Test your interface in front of it; see `test-doubles.md` |

Two exceptions worth naming: analytics events *are* the deliverable in some apps, and a serialisation format *is* a contract when another system reads it. Test those.

## Turning a bug report into a regression test

A regression test is the only test that is guaranteed to have caught a real bug. The procedure:

1. **Reproduce in the smallest harness that still fails.** Start at `testWidgets` on the single page. Drop to `test` on the repository if the page was innocent. Only promote to `integration_test` if the bug needs a real platform channel.
2. **Write the failing test first and watch it fail for the reported reason.** A test that passes before the fix is testing something else.
3. **Name it after the defect, not the fix.**
   ```dart
   testWidgets('does not crash when the todo title is empty (#412)', (tester) async { ... });
   ```
4. **Encode the exact input from the report** — the empty string, the 2.0 text scale, the timezone, the 401 body. Generic inputs reproduce generic bugs.
5. **Fix, watch it pass, then revert the fix once** and confirm it fails again. A test that passes with and without the fix is decoration.
6. **Leave the issue number in the name.** Six months later it is the only way to know whether the assertion is still meaningful.

Worked example, from "toggling a todo while offline leaves the checkbox ticked":

```dart
testWidgets('rolls the checkbox back when the write fails offline (#412)', (tester) async {
  final repository = FakeTodoRepository(todos: const [Todo(id: '1', title: 'a', done: false)])
    ..failNextWrite = true;

  await tester.pumpApp(
    const TodoListPage(),
    overrides: [todoRepositoryProvider.overrideWithValue(repository)],
  );
  await tester.pump();

  await tester.tap(find.byType(CheckboxListTile));
  await tester.pump(); // optimistic on
  await tester.pump(); // failure lands, rollback

  expect(
    tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
    isFalse,
    reason: 'optimistic update must roll back on SocketException',
  );
});
```

Note `reason:` — it turns a bare `false != true` into a sentence in the failure log.

## Choosing between a widget test and a golden test

| Question | Widget test | Golden test |
|---|---|---|
| "Is the error message shown?" | yes | no |
| "Does the button call the callback?" | yes | no |
| "Is the card 16px from the edge in dark mode?" | painful | yes |
| "Did a theme change silently restyle 40 screens?" | no | yes |
| Runs on any contributor's machine | yes | no, without a pinned environment |
| Fails with a readable message | yes | no — "pixels differ" |

A golden earns its place when the *appearance itself* is the contract and there is no cheap textual assertion for it. Everything else is a widget test.

## Coverage numbers that mean something

- Coverage is a *floor detector*, not a quality measure. 0% on a repository layer is a finding; 92% versus 94% is noise.
- Gate on "coverage must not fall on this PR" rather than an absolute threshold. Absolute thresholds get met by testing getters.
- Exclude generated files before computing anything (`test-layout.md`).
- Branch coverage (`--branch-coverage`) is more informative than line coverage for code full of `if (x != null)`.

## A minimum viable suite for a new feature

For a feature with a repository, a notifier and a page, the smallest suite that is worth having:

1. One `test` per error path in the repository (network failure, malformed payload, permission denied).
2. One provider test for the notifier's happy path and one for its failure/rollback path.
3. Three `testWidgets` for the page: loading, loaded-with-data, error-with-retry.
4. One `testWidgets` for the empty state, because it is the state nobody looks at during development.
5. Zero goldens until the component is reused in three places.
6. Zero integration tests until the feature ships; then one, covering the flow a support ticket would describe.

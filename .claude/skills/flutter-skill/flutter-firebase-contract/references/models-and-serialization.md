# Models and serialisation

The Dart model and the server's zod schema describe the same JSON. This file is about keeping them honest: what the field names are, how dates and enums cross, when to generate code and when to write it by hand, and what a nullability mismatch costs.

The envelope rules themselves — object in, object out, camelCase, no `uid` in the request, opaque cursors, no `{ success: true }` wrapper — are shared with the server and documented once, in `firebase-skill` → `firebase-ios-contract` → `references/envelope-and-naming.md`. Do not restate them; match them.

## Schema ↔ Dart

| Server (zod input) | Meaning | Dart request field |
|---|---|---|
| `z.string()` | required | `final String x;` |
| `z.string().optional()` | may be absent (`undefined`) | `final String? x;` — omit the key from `toJson` when null |
| `z.string().nullable()` | present, may be `null` | `final String? x;` — always write the key. Avoid; prefer `.optional()` |
| `z.string().default('')` | may be absent; server fills it | `final String x;` with a Dart default |
| `z.number().int()` | required int | `final int x;` |
| `z.number()` | required double | `final double x;` — decode via `as num` |
| `z.boolean()` | required bool | `final bool x;` |
| `z.enum([...])` | closed set | `enum X { ... }` |
| `z.array(T)` | list | `final List<T> x;` |
| `z.string().datetime()` | ISO-8601 | `final DateTime x;` |

| Server (output interface) | Dart response field |
|---|---|
| `x: string` | `final String x;` |
| `x: string \| null` | `final String? x;` |
| `x?: string` | `final String? x;` — but prefer `string \| null` so the key is always present |

The asymmetry matters. In a request, omitting a key and sending `null` are different things to zod: `.optional()` accepts a missing key and rejects `null`; `.nullable()` does the reverse. Write `toJson` deliberately:

```dart
Map<String, Object?> toJson() => {
      'title': title,
      if (cursor != null) 'cursor': cursor,   // .optional() — omit when absent
      'sort': sort.name,
    };
```

`{'cursor': null}` against a `z.string().optional()` field is an `invalid-argument` the app cannot see coming.

## Dates

ISO-8601 strings, both directions. Nothing else.

```dart
// Decode — the server emits Date.prototype.toISOString(), e.g. "2026-09-16T08:41:12.345Z"
final createdAt = DateTime.parse(json['createdAt'] as String);

// Encode
'startAt': startAt.toUtc().toIso8601String(),
```

- `DateTime.parse` accepts `Z`, a numeric offset, and fractional seconds. It does not need a formatter and it does not need `intl`.
- `DateTime.parse` of a string with `Z` produces a UTC `DateTime` (`isUtc == true`). Call `.toLocal()` at the point of display, never at the point of decode, or two devices in different zones disagree about what the server sent.
- Encode with `.toUtc()` first. `toIso8601String()` on a local `DateTime` emits no offset at all, and `z.string().datetime()` rejects it.
- `DateTime.tryParse` for anything the server might legitimately omit; a `FormatException` inside `fromJson` surfaces as an opaque decode failure.

**Never put a Firestore `Timestamp` into a callable request or expect one in a response.** A `Timestamp` is not a JSON type: encoding it fails the plugin's parameter assertion, and a server that returns one sends `{_seconds, _nanoseconds}`, which is not a `DateTime` on either side. `Timestamp` is legitimate in documents read through `snapshots()` and nowhere else — see `firestore-streams.md`. The server-side rule is in `firebase-skill` → `firebase-functions-pro`.

```dart
// Before — the assertion fires in debug, the call fails in release
await callable.call({'due': Timestamp.fromDate(due)});

// After
await callable.call({'due': due.toUtc().toIso8601String()});
```

Epoch numbers are the other wrong answer: ambiguous between seconds and milliseconds, and they decode to `int`, so the type no longer says "time".

## Enums

String literals on the wire, never integers. Response enums must tolerate a value the installed build has never heard of, because the server may add a case before the app updates.

```dart
enum JobStatus {
  queued,
  processing,
  done,
  failed,
  unknown;

  static JobStatus fromJson(Object? raw) => values.firstWhere(
        (v) => v.name == raw,
        orElse: () => unknown,
      );

  String toJson() => name;
}
```

- `values.byName(raw)` throws on an unknown value — that is the bug this pattern exists to avoid. Use `firstWhere` with `orElse`.
- Put `unknown` last and never send it: it is a decode fallback, not a state the server understands.
- Request enums do not need the fallback. `z.enum` on the server is closed, so the app can only usefully send cases the server already knows.
- When a Dart member name collides with a keyword (`private`, `default`, `in`), rename the member and map explicitly rather than using a raw identifier:

```dart
enum Visibility {
  personal('private'),
  shared('shared'),
  unknown('unknown');

  const Visibility(this.wire);
  final String wire;

  static Visibility fromJson(Object? raw) =>
      values.firstWhere((v) => v.wire == raw, orElse: () => unknown);

  String toJson() => wire;
}
```

## Hand-written vs generated

| Approach | Use when |
|---|---|
| Hand-written `fromJson`/`toJson` | Callable request/response types. They are small, they need `as num`/`cast<String>()` care, and the fallback behaviour for enums and unknown keys is a contract decision, not a default. |
| `json_serializable` | Large or numerous DTOs with a regular shape, especially when the server already publishes a JSON Schema. |
| `freezed` | Domain models that want `copyWith`, value equality, and union types. Pair with `json_serializable` for the JSON half. |

Versions verified on pub.dev, 2026-09-22: `json_serializable` 6.14.1 with `json_annotation >=4.12.0 <4.13.0`; `freezed` 4.0.2 with `freezed_annotation` 3.1.0 (an exact pin in freezed's own pubspec — do not put a looser constraint on it). Both need `build_runner` as a dev dependency and `dart run build_runner build --delete-conflicting-outputs`.

```dart
@JsonSerializable()
final class NoteSummary {
  const NoteSummary({required this.id, required this.title, required this.updatedAt});

  factory NoteSummary.fromJson(Map<String, dynamic> json) => _$NoteSummaryFromJson(json);

  final String id;
  final String title;
  final DateTime updatedAt;   // json_serializable emits DateTime.parse / toIso8601String

  Map<String, dynamic> toJson() => _$NoteSummaryToJson(this);
}
```

`json_serializable` already emits `DateTime.parse` for a `DateTime` field and `toIso8601String()` on the way out, which is exactly the contract. Two settings are worth being explicit about:

- `@JsonKey(includeIfNull: false)` on a field that mirrors a zod `.optional()`, so the key is omitted rather than sent as `null`.
- `@JsonKey(unknownEnumValue: MyEnum.unknown)` on every response enum. Without it the generated code throws on an unrecognised value.
- Leave `fieldRename` alone. The contract is camelCase on both sides; a snake_case field is a server bug to fix, not a generator setting to hide.

## Nullability is a contract, not a style

A Dart field typed `String` where the server sends `null` throws `TypeError` inside `fromJson` and takes the whole response with it. A field typed `String?` where the server always sends a value costs a null check at every use site forever. Neither is a preference: copy the schema.

```dart
// Server: nextCursor: string | null
final String? nextCursor;     // correct

// Server: items: NoteSummary[]   (never null, may be empty)
final List<NoteSummary> items;  // correct — not List<NoteSummary>?
```

Defend the boundary once, in `fromJson`, rather than sprinkling `?? ''` through the UI:

```dart
factory ListNotesResponse.fromJson(Map<String, dynamic> json) => ListNotesResponse(
      items: [
        for (final raw in json['items'] as List)
          NoteSummary.fromJson(raw as Map<String, dynamic>),
      ],
      nextCursor: json['nextCursor'] as String?,
    );
```

An absent key and an explicit `null` both decode to `null` for an optional field, so `as String?` covers `x?: string` and `x: string | null` alike.

## Shared-types discipline

Two languages, one shape. Pick one mechanism and enforce it in review:

1. **A contract document per function** — the zod schema and the Dart model side by side in the same Markdown file or in a doc comment above each Dart model, naming the function. Cheapest, works immediately, relies on review.
2. **Generated from the schema** — export JSON Schema from zod on the server, generate Dart with a schema-to-Dart generator, commit the output. Removes drift at the cost of a build step in two repos; verify the generator's date and enum handling against the rules above before trusting it.

Whichever you pick:

- Every Dart model that mirrors a callable shape carries a doc comment naming the function and the server type: `/// Mirrors CreateNoteOutput in functions/src/notes/createNote.ts`.
- Model files live next to the repository that uses them, not in a shared `models/` bin, so the blast radius of a contract change is one folder.
- A contract change is reviewed on both sides in the same pull request or, when the repos are separate, in linked pull requests. Adding an optional field server-first and a Dart field app-second is the only safe order; see the versioning rules in `firebase-skill` → `firebase-ios-contract` → `references/versioning.md`.

## Does not exist / common mistakes

- `Timestamp` in a callable request or response — not JSON; use ISO-8601.
- `DateTime.now()` sent without `.toUtc()` — `toIso8601String()` then emits a local time with no offset, which `z.string().datetime()` rejects.
- `DateTime.fromMillisecondsSinceEpoch(json['createdAt'])` — only correct if the server really sends millis; it usually sends a string, and this throws.
- `MyEnum.values.byName(json['status'])` — throws the day the server adds a case.
- `json['count'] as double` — a JSON `3` is an `int`; use `(json['count'] as num).toDouble()`.
- `json['tags'] as List<String>` — the value is `List<dynamic>`; use `.cast<String>()`.
- `jsonDecode(jsonEncode(result.data))` to "fix" types — it works, but it hides the real cast errors and doubles the cost; fix the `fromJson`.
- `@JsonSerializable(fieldRename: FieldRename.snake)` — breaks the camelCase contract.
- `freezed_annotation: ^4.0.0` alongside `freezed: 4.0.2` — freezed 4.0.2 pins `freezed_annotation` to exactly 3.1.0.
- A model with `Map<String, dynamic> extra` to catch unknown server fields — unknown fields are already ignored; the field just invites someone to depend on them.

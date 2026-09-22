# Envelope and naming

The contract is JSON. The Firebase SDK wraps the request as `{ "data": ... }` and the response as `{ "result": ... }` on the wire; both sides only ever see the inner value. Everything below is about that inner value.

## Function names

- The deployed name is the TypeScript export name. It is what `httpsCallable("...")` receives. Keep the three identical: file name, export, client string.
- camelCase, verb-first, from the client's point of view: `createNote`, `listNotes`, `redeemCode`, `chat`, `startScan`, `getBootstrap`.
- Do not use `domain.verb` (`notes.create`). A dot is not a valid function name; it also collides with grouped exports (`export const notes = { create }` deploys as `notes-create`) and makes `--only functions:notes.create` ambiguous. If you want grouping, use a prefix: `notesCreate`, `notesList` — but plain verbs read better in the app.
- Versioned: `createNoteV2`. Capital V, no dot, no underscore. See `versioning.md`.
- Triggers, scheduled jobs, and task workers are not part of the client contract; name them for the server (`onNoteWritten`, `processScan`). They never appear in Swift.
- Keep a single list of client-facing names in Swift:

```swift
enum FunctionName {
  static let createNote = "createNote"
  static let listNotes = "listNotes"
  static let chat = "chat"
  static let startScan = "startScan"
}
```

## Request envelope

Always an object, never a scalar or array at the top level, even for one field:

```ts
// server
const GetNoteInput = z.object({ noteId: z.string().min(1).max(128) });
```

```swift
// client
struct GetNoteRequest: Codable, Equatable, Sendable { let noteId: String }
```

Reason: adding a second field later is additive; changing a top-level string to an object is breaking. Void requests send `{}`:

```swift
struct EmptyRequest: Codable, Equatable, Sendable { init() {} }
```

Do not put `uid` in the request. The server reads it from `request.auth`. A `uid` field in the request is either ignored (confusing) or trusted (a security bug).

Do not put an `action`/`type` discriminator in the request to multiplex several operations through one function. One operation, one function. It keeps options, logs, and `--only` targets per operation and lets the Swift side have one `Callable` per operation.

## Response envelope

Always an object. Void responses return `{}`.

```ts
export interface DeleteNoteOutput {}          // return {}
export interface ListNotesOutput { items: NoteSummary[]; nextCursor: string | null }
```

```swift
struct EmptyResponse: Codable, Equatable, Sendable {}
struct ListNotesResponse: Codable, Equatable, Sendable {
  let items: [NoteSummary]
  let nextCursor: String?
}
```

Do not wrap in `{ success: true, data: ... }` or `{ error: null, result: ... }`. Failure is an `HttpsError`, not a field; the client's `try await` already distinguishes the two paths. A `success` boolean invites the server to return 200 with `success: false` and a message, which bypasses the whole error-mapping contract.

Do not return the entire Firestore document. Map to an explicit output type so the client cannot depend on a field you did not intend to expose and so `Timestamp` never leaks.

## Field naming

- camelCase on both sides: `createdAt`, `noteId`, `isPinned`. Never snake_case; never `CodingKeys` to bridge the two. If the server wraps a third-party payload with snake_case (RevenueCat, Apple), map it to camelCase on the server before returning.
- Booleans are adjectives or `is`/`has` prefixed: `isPinned`, `hasAttachments`. Not `pinned: true` next to `deleted: false` next to `archive: 1`.
- IDs end in `Id`: `noteId`, `jobId`, `userId` (not `ID`, not `_id`, not `id` for a foreign key). The document's own id is `id`.
- Counts end in `Count`; timestamps end in `At`; durations end in `Seconds`/`Millis` and say which.

## Dates

ISO-8601 strings with fractional seconds and a `Z` suffix, produced by `Date.prototype.toISOString()`:

```ts
createdAt: snap.get("createdAt").toDate().toISOString()   // "2026-09-16T08:41:12.345Z"
```

```swift
let createdAt: Date   // decoded with a strategy that accepts fractional seconds — see swift-client.md
```

Never:

- Firestore `Timestamp` — does not serialise through a callable (the client sees `{ _seconds, _nanoseconds }` or the call fails). Convert with `.toDate().toISOString()`.
- Epoch numbers — ambiguous seconds vs millis, and `Int` on the Swift side loses the `Date` type. If a third-party gives you millis (RevenueCat `expiration_at_ms`), convert on the server.
- `Date` objects inside the returned object without `.toISOString()` — they do serialise correctly, but the TS output type would say `Date` while the wire says `string`; keep the type honest.

The client sends dates the same way: `ISO8601DateFormatter` with `.withFractionalSeconds`, or the shared encoder's `dateEncodingStrategy`. The server validates with `z.string().datetime()` (accepts `Z` and fractional seconds by default; pass `{ offset: true }` if you accept offsets).

## Optionals and defaults

| Server (zod input) | Meaning | Swift request |
|---|---|---|
| `z.string()` | required | `let x: String` |
| `z.string().optional()` | may be absent (`undefined`) | `var x: String? = nil` — encoder omits `nil` keys by default |
| `z.string().nullable()` | must be present, may be `null` | `let x: String?` + encoder that writes `null` — avoid; prefer `.optional()` |
| `z.string().default("")` | may be absent; server fills it | `var x: String = ""` — the client can also omit it |

| Server (output interface) | Swift response |
|---|---|
| `x: string` | `let x: String` |
| `x: string \| null` | `let x: String?` (Swift decodes both `null` and missing as `nil` for optionals) |
| `x?: string` | `let x: String?` — but prefer `string \| null` in outputs so the JSON always has the key |

Rules:

- Inputs: prefer `.optional()` + `.default()` over `.nullable()`. Swift's `JSONEncoder`/`FirebaseDataEncoder` omits `nil` optionals, which zod sees as `undefined`, which `.nullable()` rejects.
- Outputs: prefer `T | null` over `T?` so the key is always present and a missing key on the client is a real bug, not a silent `nil`.
- Never let `undefined` reach the response: set `ignoreUndefinedProperties` only for Firestore writes, and build outputs explicitly.

## Enums

String literals on the wire. Never integers.

```ts
export const NoteVisibility = z.enum(["private", "shared"]);
export type NoteVisibility = z.infer<typeof NoteVisibility>;
```

```swift
enum NoteVisibility: String, Codable, Equatable, Sendable {
  case `private`, shared
}
```

When the server may add cases before the app updates, give the Swift enum a tolerant decoder:

```swift
enum JobStatus: String, Codable, Equatable, Sendable {
  case queued, processing, done, failed, unknown

  init(from decoder: Decoder) throws {
    let raw = try decoder.singleValueContainer().decode(String.self)
    self = JobStatus(rawValue: raw) ?? .unknown
  }
}
```

Do this for every enum in a *response*. Enums in *requests* are closed on the server side (`z.enum` rejects unknown), so the app can only send cases the server already knows.

## Nested objects and arrays

- Nested objects are separate named types on both sides (`NoteSummary`, `Attachment`), not inline anonymous shapes. Name them identically.
- Arrays are homogeneous. No `[string | number]`, no tuples.
- Maps with dynamic keys (`Record<string, number>`) are allowed and decode to `[String: Int]`, but prefer an array of `{ key, value }` objects when the key set is unbounded or needs ordering.
- Keep response depth ≤ 3. Deeper means the callable is doing the client's aggregation work; split the endpoint or return ids and let the client read Firestore.

## Pagination

Cursor-based, opaque, with a fixed shape:

```ts
const ListNotesInput = z.object({
  limit: z.number().int().min(1).max(50).default(20),
  cursor: z.string().max(512).optional(),        // opaque; produced by a previous response
  sort: z.enum(["updatedAtDesc", "titleAsc"]).default("updatedAtDesc"),
});

export interface ListNotesOutput {
  items: NoteSummary[];
  nextCursor: string | null;                     // null = no more pages
}
```

The cursor encodes whatever `startAfter` needs — typically `base64url(JSON.stringify([updatedAtMillis, id]))`. The client never inspects it. The server validates it (`z.string()` then decode + shape check → `invalid-argument` on failure).

```swift
struct ListNotesRequest: Codable, Equatable, Sendable {
  var limit: Int = 20
  var cursor: String? = nil
  var sort: NoteSort = .updatedAtDesc
}
struct ListNotesResponse: Codable, Equatable, Sendable {
  let items: [NoteSummary]
  let nextCursor: String?
}
```

Do not: `page: number` (offset-based, bills every skipped document and drifts under concurrent writes); `hasMore: boolean` next to `nextCursor` (redundant, can disagree); `lastId` as the cursor (insufficient once you sort on anything but id).

## Money, sizes, and units

- Money: integer minor units + ISO currency code: `{ amountMinor: 1990, currency: "VND" }`. Never floats.
- Sizes: bytes as integers, `sizeBytes`.
- Percentages: `0`–`100` integers or `0.0`–`1.0` doubles, named accordingly (`progressPercent` vs `progress`). Pick one per project.

## Does not exist / common mistakes

- `httpsCallable("notes.create")` — a dotted name is not a deployable export.
- Sending a top-level string or array as the request — works today, breaks the first time you add a field.
- `uid` in the request body — server must use `request.auth.uid`.
- `{ success: false, error: "..." }` with HTTP 200 — bypasses error mapping; throw `HttpsError`.
- `Timestamp` in a response — does not encode; convert to ISO string.
- `snake_case` from a third-party passed through — map on the server.
- Integer enums — unreadable in logs, unsafe to reorder.
- `page`/`offset` pagination — use an opaque cursor.
- Different envelope styles across functions in the same project — pick one and enforce it in review.

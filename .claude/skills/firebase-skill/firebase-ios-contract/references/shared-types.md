# Shared types

The zod schema is the source of truth. The Swift struct is a hand-written mirror, checked in review against the schema field by field. Codegen is optional and covered at the end; do not adopt it until the hand-written mirror has become a maintenance problem.

## Type correspondence

| zod (TS) | JSON | Swift |
|---|---|---|
| `z.string()` | string | `String` |
| `z.string().datetime()` | ISO-8601 string | `Date` (custom strategy, `swift-client.md`) |
| `z.number()` | number | `Double` |
| `z.number().int()` | integer | `Int` |
| `z.boolean()` | boolean | `Bool` |
| `z.enum(["a","b"])` | string | `enum X: String, Codable` |
| `z.array(T)` | array | `[T]` |
| `z.object({...})` | object | `struct` |
| `z.record(z.string(), T)` | object | `[String: T]` |
| `T.optional()` (input) | key absent | `var x: T? = nil` |
| `T.nullable()` (output) | `null` | `let x: T?` |
| `T.default(v)` (input) | key absent or value | `var x: T = v` |
| `z.union([A, B])` discriminated | object with `type` | `enum` with associated values + custom `Codable` |
| `z.literal("x")` | `"x"` | `String` checked in init, or drop from Swift |
| `z.string().uuid()` | string | `UUID` — only if the server always emits lowercase canonical form; else `String` |
| `z.string().url()` | string | `URL` — decodes only if it is a valid URL; safer as `String` if the server may return `""` |

Keep numbers simple: `Int` or `Double`, never `Decimal` over JSON (precision is lost in transit anyway). Money is integer minor units.

## Side by side

```ts
// functions/src/notes/types.ts
import { z } from "zod";

export const NoteVisibility = z.enum(["private", "shared"]);

export const Attachment = z.object({
  id: z.string().min(1),
  kind: z.enum(["image", "pdf"]),
  storagePath: z.string().min(1),
  sizeBytes: z.number().int().nonnegative(),
});

export const CreateNoteInput = z.object({
  client: ClientInfo,
  title: z.string().min(1).max(200),
  body: z.string().max(20_000).default(""),
  visibility: NoteVisibility.default("private"),
  tags: z.array(z.string().min(1).max(30)).max(10).default([]),
  attachments: z.array(Attachment).max(5).default([]),
  remindAt: z.string().datetime().optional(),
});

export interface NoteSummary {
  id: string;
  title: string;
  visibility: z.infer<typeof NoteVisibility>;
  tagCount: number;
  updatedAt: string;        // ISO-8601
  remindAt: string | null;  // ISO-8601
}

export interface CreateNoteOutput {
  note: NoteSummary;
}
```

```swift
// Contract/Notes.swift
enum NoteVisibility: String, Codable, Equatable, Sendable {
  case `private`, shared
}

enum AttachmentKind: String, Codable, Equatable, Sendable {
  case image, pdf, unknown
  init(from decoder: Decoder) throws {
    self = AttachmentKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
  }
}

struct Attachment: Codable, Equatable, Sendable {
  let id: String
  let kind: AttachmentKind
  let storagePath: String
  let sizeBytes: Int
}

struct CreateNoteRequest: Codable, Equatable, Sendable {
  var client = ClientInfo()
  var title: String
  var body: String = ""
  var visibility: NoteVisibility = .private
  var tags: [String] = []
  var attachments: [Attachment] = []
  var remindAt: Date? = nil
}

struct NoteSummary: Codable, Equatable, Sendable, Identifiable {
  let id: String
  let title: String
  let visibility: NoteVisibility
  let tagCount: Int
  let updatedAt: Date
  let remindAt: Date?
}

struct CreateNoteResponse: Codable, Equatable, Sendable {
  let note: NoteSummary
}
```

Review checklist for a pair like this:

1. Same field names, same order (order is not semantic, but it makes the diff readable).
2. Every zod `.default()` / `.optional()` in an input ↔ `var` with a default / `= nil` in the request.
3. Every `T | null` in an output ↔ `let x: T?` in the response.
4. Every enum in a response has an `unknown` fallback in Swift, or a written justification why the case set is closed.
5. Every date is `z.string().datetime()` / `string` ↔ `Date`.
6. Nested objects are named types on both sides, not inline.
7. Request structs are `var` with defaults (built up by the reducer); response structs are `let`.
8. Both sides are in files named after the domain (`notes/types.ts` ↔ `Contract/Notes.swift`).

## Discriminated unions

Server:

```ts
export const JobResult = z.discriminatedUnion("type", [
  z.object({ type: z.literal("ocr"), text: z.string(), pageCount: z.number().int() }),
  z.object({ type: z.literal("summary"), summary: z.string() }),
]);
```

Swift:

```swift
enum JobResult: Equatable, Sendable {
  case ocr(text: String, pageCount: Int)
  case summary(String)
  case unknown(type: String)
}

extension JobResult: Codable {
  private enum CodingKeys: String, CodingKey { case type, text, pageCount, summary }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    let type = try c.decode(String.self, forKey: .type)
    switch type {
    case "ocr":     self = .ocr(text: try c.decode(String.self, forKey: .text), pageCount: try c.decode(Int.self, forKey: .pageCount))
    case "summary": self = .summary(try c.decode(String.self, forKey: .summary))
    default:        self = .unknown(type: type)
    }
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .ocr(text, pageCount):
      try c.encode("ocr", forKey: .type); try c.encode(text, forKey: .text); try c.encode(pageCount, forKey: .pageCount)
    case let .summary(summary):
      try c.encode("summary", forKey: .type); try c.encode(summary, forKey: .summary)
    case let .unknown(type):
      try c.encode(type, forKey: .type)
    }
  }
}
```

Use a flat `type` discriminator with sibling fields (as above), not a wrapper key per case (`{ ocr: {...} }`). It is what `z.discriminatedUnion` produces and it decodes cleanly in Swift.

## Where the files live

Server: `functions/src/<domain>/types.ts` exports schemas and output interfaces; the `onCall` file imports them. Tests import the same schemas to build fixtures.

iOS: a `Contract` SwiftPM target (or folder) with one file per domain, depending on nothing but `Foundation`. The dependency clients (`NotesClient`) live in a separate target that imports `Contract`; the live values live in a third that imports `FirebaseFunctions`. Previews and unit tests import `Contract` without linking Firebase.

## Contract tests (cheap, high value)

Server: snapshot the JSON schema of each input and output so an accidental change shows up in review.

```ts
// functions/test/contract.test.ts
import { zodToJsonSchema } from "zod-to-json-schema";
import { expect, it } from "vitest";
import { CreateNoteInput } from "../src/notes/types.js";

it("CreateNoteInput schema is stable", () => {
  expect(zodToJsonSchema(CreateNoteInput, "CreateNoteInput")).toMatchSnapshot();
});
```

iOS: decode a fixture JSON captured from the emulator for each response type.

```swift
@Test func decodesCreateNoteResponseFixture() throws {
  let data = try Data(contentsOf: Bundle.module.url(forResource: "createNote.response", withExtension: "json")!)
  let response = try FirebaseJSON.jsonDecoder.decode(CreateNoteResponse.self, from: data)
  #expect(response.note.id == "n1")
}
```

Regenerate fixtures from the emulator when the server changes (`curl` the callable endpoint with `{"data": {...}}` and save the `result`).

## Optional codegen

When the hand-written mirror drifts too often, generate Swift from the zod schemas. Pipeline:

```bash
# functions/
npm i -D zod-to-json-schema quicktype
```

```ts
// functions/scripts/emit-schema.ts
import { writeFileSync } from "node:fs";
import { zodToJsonSchema } from "zod-to-json-schema";
import * as notes from "../src/notes/types.js";

const definitions = {
  CreateNoteInput: zodToJsonSchema(notes.CreateNoteInput),
  Attachment: zodToJsonSchema(notes.Attachment),
};
writeFileSync("schema/notes.json", JSON.stringify({ definitions }, null, 2));
```

```bash
npx tsx scripts/emit-schema.ts
npx quicktype --src-lang schema --lang swift --src schema/notes.json \
  --out ../ios/Contract/Generated/Notes.swift \
  --struct-or-class struct --protocol equatable --acronym-style camel
```

Caveats, which is why this stays optional:

- Output interfaces (`CreateNoteOutput`) are TS interfaces, not zod schemas. To generate them you must define outputs as zod schemas too (`z.object`) and `z.infer` the TS type — fine, and it lets the server validate its own output in tests.
- quicktype emits `Codable` with its own date handling (it maps `format: "date-time"` to `Date` only with `--support-date-time`... verify against quicktype docs) and no `unknown` enum fallback. Post-process or keep enums hand-written.
- quicktype's `Sendable` support and Swift 6 strict-concurrency output should be checked per version; you may need `--swift-5-support` off and a sed pass for `Sendable`.
- Generated files are committed and reviewed like hand-written ones. Regenerate in CI and fail on diff so the app repo cannot lag.

Do not go the other way (Swift → TS). The server validates; its schema must be the origin.

## Does not exist / common mistakes

- `Codable` structs with `CodingKeys` that rename to snake_case — the contract is camelCase; fix the server.
- `Any`/`AnyCodable` fields "for flexibility" — untyped payloads cannot be reviewed against a schema. Use a discriminated union.
- `Double` for money, `Int` for dates — units and precision problems. Minor units and ISO strings.
- `let` properties on request structs with a memberwise init — forces every call site to pass every default. Use `var` with defaults.
- Swift enum without `unknown` mirroring a server enum that grows — decode crash on old builds.
- Two zod schemas for the same concept (one in the callable, one in the trigger) — one `types.ts` per domain.
- Assuming `z.infer` output types are the wire types — `Date`/`Timestamp` in TS types must be converted to strings before return; declare output interfaces with `string`.

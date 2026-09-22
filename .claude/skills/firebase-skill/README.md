# Server Skills for Claude Code

**8 skills for building a Firebase Cloud Functions backend that serves an iOS app with Claude Code** — callable API design, the Swift/TCA client contract, security, Firestore data flows, push notifications, Gemini/LLM pipelines, testing, and deployment.

[github.com/doxuto/Server-AI-SKILL](https://github.com/doxuto/Server-AI-SKILL)

This is the server-side sibling of [iOS-AI-SKILL](https://github.com/doxuto/iOS-AI-SKILL). The two bundles are meant to be installed together: the server skills hand off to `tca-pro`, `swift-concurrency-pro`, `swiftui-pro`, and `xcuitest-pro` wherever the work crosses into the app, rather than restating them.

Install into `~/.claude/skills/` and Claude loads the matching skill automatically based on what you ask for.

## The skills

### Functions and the app contract

| Skill | What it does |
|---|---|
| **`firebase-functions-pro`** | Cloud Functions 2nd gen in TypeScript — `onCall`, `onRequest`, `HttpsError`, params and secrets, runtime options, cold starts, v1 → v2 migration, and every common hallucination with its correct replacement |
| **`firebase-ios-contract`** | The request/response contract between a callable and the Swift client — zod ↔ `Codable`, `Callable<Request, Response>`, error mapping to `FunctionsErrorCode`, a `@DependencyClient` for TCA, streaming, versioning, when to use a Firestore listener instead |

### Security and data

| Skill | What it does |
|---|---|
| **`firebase-security-pro`** | Auth in functions, custom claims, App Check / App Attest, `firestore.rules` and `storage.rules` patterns, Sign in with Apple + account deletion, rate limiting, secrets and PII hygiene, a threat checklist |
| **`firestore-data-pro`** | Data modeling, v2 Firestore triggers, transactions and batches, idempotency, `onSchedule`, `onTaskDispatched` task queues, Storage triggers, queries and indexes, maintenance |

### Push and AI

| Skill | What it does |
|---|---|
| **`fcm-push-pro`** | FCM → APNs for iOS — token registry, the full `aps` payload table, `sendEachForMulticast`, silent and rich pushes, the iOS client half, notification patterns |
| **`firebase-ai-pro`** | Gemini from functions via `@google/genai` or Genkit — structured output, streaming to iOS, a document OCR/extraction pipeline, prompting and safety, cost control, when Firebase AI Logic on the client is enough |

### Testing and shipping

| Skill | What it does |
|---|---|
| **`firebase-testing-pro`** | Emulator Suite, `firebase-functions-test`, rules unit testing, integration tests, the iOS app against the emulator, CI |
| **`firebase-deploy-pro`** | dev/staging/prod projects, `firebase.json`, deploy workflow, GitHub Actions with Workload Identity, monitoring and alerts, cost, rollback and incidents, a release checklist |

## Install

Install for every project on your machine:

```bash
git clone git@github.com:doxuto/Server-AI-SKILL.git
mkdir -p ~/.claude/skills
cp -R Server-AI-SKILL/*/ ~/.claude/skills/
```

Over HTTPS instead, if you have no SSH key set up:

```bash
git clone https://github.com/doxuto/Server-AI-SKILL.git
```

Install into a single project, so the skills travel with the repo and your team gets them too:

```bash
cd /path/to/your-backend
mkdir -p .claude/skills
cp -R /path/to/Server-AI-SKILL/*/ .claude/skills/
```

Verify with `/skills` in Claude Code — all 8 should be listed. Skills load by their `description`, so you never invoke them by name: ask "review this callable", "write the Firestore rules for notes", or "send a push when a note is shared" and the matching skill loads itself.

### Updating

```bash
cd /path/to/Server-AI-SKILL
git pull
cp -R ./*/ ~/.claude/skills/
```

`cp -R` overwrites the skill folders in place and leaves any other skills you have alone.

### Staying on a symlink instead

```bash
git clone git@github.com:doxuto/Server-AI-SKILL.git ~/dev/Server-AI-SKILL
mkdir -p ~/.claude/skills
for skill in ~/dev/Server-AI-SKILL/*/; do
  ln -sfn "$skill" ~/.claude/skills/"$(basename "$skill")"
done
```

Each skill is a folder containing `SKILL.md` plus reference files that Claude loads on demand, so an unused reference costs no context.

## How the skills fit together

A typical feature touches several of them, in roughly this order:

1. **`firebase-ios-contract`** — decide the function name, the zod schema, and the `Codable` mirror before writing either side.
2. **`firebase-functions-pro`** — write the `onCall` handler: auth check, validation, mapped errors, structured logs.
3. **`firebase-security-pro`** — App Check on the function, rules for whatever the client reads directly, a quota if the call costs money.
4. **`firestore-data-pro`** — any trigger, transaction, scheduled job, or task queue the feature needs. Long jobs write a status document; the app listens.
5. **`fcm-push-pro`** / **`firebase-ai-pro`** — when the feature notifies the user or calls a model.
6. **`firebase-testing-pro`** — handler tests, rules tests, and the emulator run the iOS app points at.
7. **`firebase-deploy-pro`** — staging first, then production, server before the app release.

On the iOS side, the dependency that wraps `Functions` is designed with `tca-pro` (`references/dependencies.md`), and the streaming loop follows `swift-concurrency-pro`.

## Versions these skills target

| | |
|---|---|
| Functions | `firebase-functions` 6.x, 2nd gen (`firebase-functions/v2/*`), Node 22 |
| Admin SDK | `firebase-admin` 13.x, modular imports (`firebase-admin/app`, `firebase-admin/firestore`, …) |
| iOS | Firebase iOS SDK 12.x (`Callable<Request, Response>` and `.stream(_:)` need ≥ 11.8), Swift 6.2, TCA 1.26+ |
| AI | `@google/genai` (unified SDK), Genkit 1.x, `onCallGenkit` |
| Testing | `firebase-functions-test` 3.x, `@firebase/rules-unit-testing` 4.x, vitest |
| Region | Examples use `asia-southeast1`; change `setGlobalOptions` and the Swift `Functions.functions(region:)` together |

Where a skill documents an API that arrived in a specific release, it says so, rather than assuming the latest.

## A note on accuracy

Skills that assert API surface are only as good as their verification. The v2 function signatures, admin SDK calls, and Swift `FirebaseFunctions` API in this bundle were written from the Firebase reference documentation and SDK sources. Where an exact flag or field could not be confirmed, the text says **"verify against firebase docs"** next to it instead of guessing a plausible name.

Things that are wrong in circulating Firebase examples and are called out here:

- `(data, context)` handler signature with `context.auth` — that is v1. v2 is `(request)` with `request.auth`, `request.data`, `request.app`.
- `firebase-functions/v2/auth` — does not exist. User lifecycle triggers (`auth.user().onCreate/onDelete`) are v1 only; v2 has the blocking `beforeUserCreated` / `beforeUserSignedIn` in `v2/identity`.
- `runWith({...})` — v1 only. v2 takes an options object as the first argument.
- `functions.config()` — deprecated and removed for new deployments. Use params and `defineSecret`.
- `sendMulticast` / `sendAll` / `sendToDevice` — removed. Use `sendEach` / `sendEachForMulticast`.
- `@google/generative-ai` — deprecated. Use `@google/genai`.
- Returning a Firestore `Timestamp` from a callable — it does not encode. Send an ISO-8601 string.

If you extend these skills, verify against primary sources before adding an API, and prefer saying "I'm not sure this exists" over writing a plausible-looking name.

## Credits

Bundle written and maintained by **[doxuto](https://github.com/doxuto)**.

## License

MIT. Copyright © doxuto.

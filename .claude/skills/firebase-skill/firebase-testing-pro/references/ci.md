# CI — running the emulator suite in GitHub Actions

One job, one `emulators:exec`, all four test layers, debug logs uploaded on failure. Deploy jobs live in `firebase-deploy-pro` → `references/github-actions.md`; this job is the gate they depend on.

## Requirements

- **Java** — the Firestore, Storage, Pub/Sub and UI emulators are jars. `actions/setup-java@v4` with Temurin 21. (Older firebase-tools accepted JDK 11; pin the CLI and JDK together and verify against firebase docs when bumping.)
- **Node 22** — matches `engines.node` in `functions/package.json` and the `nodejs22` runtime.
- **firebase-tools** — pinned, installed with `npm ci` from `functions/devDependencies` (`"firebase-tools": "^14.0.0"`) or globally with `npm i -g firebase-tools@14`. Pinning avoids the emulator jar changing under you.
- **Emulator jar cache** — jars download to `~/.cache/firebase/emulators` on first run (100+ MB). Cache the directory keyed on the firebase-tools version.
- **No secrets** — `demo-` project, no service account, no `FIREBASE_TOKEN`. If the job needs a secret, something is wrong in the test design.

## Workflow

```yaml
# .github/workflows/functions-test.yml
name: functions-test

on:
  pull_request:
    paths: ["Server/**", ".github/workflows/functions-test.yml"]
  push:
    branches: [main]
    paths: ["Server/**"]

concurrency:
  group: functions-test-${{ github.ref }}
  cancel-in-progress: true

defaults:
  run:
    working-directory: Server/functions

jobs:
  test:
    runs-on: ubuntu-latest
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v4

      - uses: actions/setup-node@v4
        with:
          node-version: 22
          cache: npm
          cache-dependency-path: Server/functions/package-lock.json

      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 21

      - name: Cache emulator jars
        uses: actions/cache@v4
        with:
          path: ~/.cache/firebase/emulators
          key: firebase-emulators-${{ runner.os }}-${{ hashFiles('Server/functions/package-lock.json') }}
          restore-keys: firebase-emulators-${{ runner.os }}-

      - run: npm ci
      - run: npm run lint
      - run: npm run build          # the Functions emulator loads lib/, not src/

      - name: Pure unit tests (no emulator)
        run: npx vitest run --dir test/unit --exclude '**/*.emulator.test.ts'

      - name: Emulator-backed tests (unit + rules + integration)
        working-directory: Server
        run: |
          npx firebase emulators:exec \
            --only functions,firestore,auth,storage \
            --project demo-snaptool \
            --import ./seed \
            "npm --prefix functions run test:ci"
        env:
          CI: "true"

      - name: Upload emulator logs
        if: failure()
        uses: actions/upload-artifact@v4
        with:
          name: emulator-logs-${{ github.run_id }}
          path: |
            Server/*-debug.log
            Server/functions/coverage/rules-coverage.json
          if-no-files-found: ignore
```

```json
// functions/package.json — one script the CI job calls inside emulators:exec
{
  "scripts": {
    "test:ci": "vitest run --dir test/unit && vitest run --dir test/rules && vitest run --dir test/integration"
  }
}
```

Three sequential `vitest run` invocations rather than one: each layer clears the emulator differently (`clearFirestore` vs `env.clearFirestore()` vs `--import` seed), and a single run with `fileParallelism: false` would still interleave their `beforeEach` semantics badly. Each invocation exits non-zero on failure and stops the chain.

## Emulator log files

`emulators:exec` writes `firebase-debug.log`, `firestore-debug.log`, `ui-debug.log`, `pubsub-debug.log` into the directory containing `firebase.json`. `functions` output (your `logger.*` calls) goes to stdout of the job and into `firebase-debug.log`. Upload all `*-debug.log` on failure; a trigger that never fired is diagnosed from `firestore-debug.log` (the write) and `firebase-debug.log` (the function registration and invocation).

Add to `.gitignore`: `*-debug.log`, `functions/lib/`, `functions/.env.local`, `functions/.secret.local`, `.firebase/`.

## Speed

| Step | Typical time | Levers |
|---|---|---|
| `npm ci` | 20–40 s | `cache: npm` on setup-node |
| jar download | 30–60 s uncached, 0 cached | `actions/cache` |
| emulator boot | 8–15 s | `--only` the emulators you need; drop `ui` (it is off by default in `exec`) |
| unit + rules | 5–20 s | keep them plain |
| integration | 10–60 s | one test per wire path, not per input variation |

Total under 3 minutes is normal. If it drifts past 5, integration tests have taken over unit tests' job — see `test-strategy.md`.

## Optional: iOS UI tests in the same job (macOS runner)

The iOS repo's CI (owned by `xcuitest-pro`) can start the emulator on a macOS runner before `xcodebuild test`:

```yaml
  ios-ui:
    runs-on: macos-15
    timeout-minutes: 45
    steps:
      - uses: actions/checkout@v4
        with: { repository: doxuto/snaptool-server, path: Server }     # or a monorepo checkout
      - uses: actions/checkout@v4
        with: { path: iOS }
      - uses: actions/setup-node@v4
        with: { node-version: 22 }
      - uses: actions/setup-java@v4
        with: { distribution: temurin, java-version: 21 }
      - run: npm ci && npm run build
        working-directory: Server/functions
      - name: Start emulators in the background
        working-directory: Server
        run: |
          npx firebase emulators:start --only functions,firestore,auth,storage --project demo-snaptool --import ./seed > emulator.log 2>&1 &
          for i in $(seq 1 60); do curl -sf http://127.0.0.1:4400/emulators > /dev/null && break; sleep 1; done
      - name: Run UI tests
        working-directory: iOS
        run: |
          xcodebuild test -scheme SnapTool -destination 'platform=iOS Simulator,name=iPhone 16' \
            -testPlan UITests-Emulator -resultBundlePath TestResults.xcresult
      - uses: actions/upload-artifact@v4
        if: failure()
        with: { name: ios-ui-failure, path: "iOS/TestResults.xcresult\nServer/emulator.log" }
```

`http://127.0.0.1:4400/emulators` is the Emulator Hub's discovery endpoint; it answers once every emulator is up. The test plan `UITests-Emulator` passes `-useFirebaseEmulator` as a launch argument (test plan → Configurations → Arguments Passed On Launch), so the Swift gate in `ios-against-emulator.md` activates.

## Branch protection

Require the `functions-test / test` check on `main`. The staging deploy workflow in `firebase-deploy-pro` uses `workflow_run` or a `needs:` on this job so nothing deploys without a green emulator run.

## Does not exist / common mistakes

- `firebase emulators:exec` on a runner without Java → "Could not spawn `java -version`". Add `setup-java`.
- `npx firebase-tools` without a pinned version → resolves to latest on every run; emulator behaviour changes silently. Pin in `devDependencies`.
- Running `emulators:exec` from `Server/functions` — `firebase.json` is in `Server/`; the CLI walks up to find it, but `--import ./seed` is then relative to the wrong directory. Set `working-directory: Server`.
- `FIREBASE_TOKEN` / service-account secrets on the test job — not needed for `demo-` projects; remove them so a test can never touch a real project.
- Uploading `node_modules` or `lib/` as artifacts — only the `*-debug.log` files and the rules coverage JSON are worth keeping.
- `ports already in use` on self-hosted runners — a previous job's emulator survived. Add `pkill -f "firebase.*emulators" || true` to a pre-step, or use ephemeral runners.

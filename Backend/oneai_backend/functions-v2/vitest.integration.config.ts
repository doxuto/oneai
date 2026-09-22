import { defineConfig } from "vitest/config";

/**
 * Integration tests: handlers against the real Firestore emulator.
 * Run ONLY under `firebase emulators:exec` (npm run test:integration).
 * firebase-testing-pro: never mock firebase-admin; shared emulator ⇒ no
 * file parallelism.
 */
export default defineConfig({
  test: {
    include: ["test/integration/**/*.test.ts", "test/rules/**/*.test.ts"],
    environment: "node",
    fileParallelism: false,
    testTimeout: 15_000,
    hookTimeout: 15_000,
  },
});

import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    environment: "node",
    // firebase-testing-pro: the emulator is shared state, so no file parallelism.
    fileParallelism: false,
  },
});

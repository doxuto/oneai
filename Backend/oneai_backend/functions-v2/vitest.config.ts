import { defineConfig } from "vitest/config";

/** Unit tests: pure logic, no Firestore. Run anywhere, fast. */
export default defineConfig({
  test: {
    include: ["test/unit/**/*.test.ts"],
    environment: "node",
  },
});

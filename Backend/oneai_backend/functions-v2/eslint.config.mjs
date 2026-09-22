import tseslint from "@typescript-eslint/eslint-plugin";
import tsparser from "@typescript-eslint/parser";

export default [
  { ignores: ["lib/**", "node_modules/**"] },
  {
    files: ["src/**/*.ts", "test/**/*.ts"],
    languageOptions: {
      parser: tsparser,
      parserOptions: { ecmaVersion: 2022, sourceType: "module" },
    },
    plugins: { "@typescript-eslint": tseslint },
    rules: {
      // firebase-functions-pro: console.log is banned, use the logger wrapper.
      "no-console": "error",
      "no-restricted-imports": ["error", {
        paths: [{
          name: "firebase-functions",
          message: "Import from firebase-functions/v2/* — v1 paths only for auth triggers.",
        }],
      }],
      "@typescript-eslint/no-explicit-any": "error",
      "@typescript-eslint/no-unused-vars": ["error", { argsIgnorePattern: "^_" }],
      "eqeqeq": ["error", "always"],
      "prefer-const": "error",
    },
  },
];

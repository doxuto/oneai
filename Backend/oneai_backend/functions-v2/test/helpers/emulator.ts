/**
 * Emulator helpers. Every test run uses a `demo-` project id — never a real
 * project, never a service-account file.
 */
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore, type Firestore } from "firebase-admin/firestore";

export const TEST_PROJECT = "demo-oneai";

export function requireEmulator(): void {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error(
      "FIRESTORE_EMULATOR_HOST is not set — run via `npm run test:integration` " +
        "(firebase emulators:exec), not `vitest` directly.",
    );
  }
}

export function testDb(): Firestore {
  requireEmulator();
  if (getApps().length === 0) initializeApp({ projectId: TEST_PROJECT });
  const db = getFirestore();
  db.settings({ ignoreUndefinedProperties: true });
  return db;
}

/** Wipe the emulator between tests via its REST endpoint. */
export async function clearFirestore(projectId: string = TEST_PROJECT): Promise<void> {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  if (!host) throw new Error("FIRESTORE_EMULATOR_HOST not set");
  const res = await fetch(
    `http://${host}/emulator/v1/projects/${projectId}/databases/(default)/documents`,
    { method: "DELETE" },
  );
  if (!res.ok) throw new Error(`clearFirestore failed: ${res.status}`);
}

/** Poll until `probe` returns a truthy value or the timeout elapses. */
export async function waitFor<T>(
  probe: () => Promise<T | null | undefined | false>,
  { timeoutMs = 5000, intervalMs = 100 } = {},
): Promise<T> {
  const deadline = Date.now() + timeoutMs;
  for (;;) {
    const v = await probe();
    if (v) return v;
    if (Date.now() > deadline) throw new Error(`waitFor: timed out after ${timeoutMs}ms`);
    await new Promise((r) => setTimeout(r, intervalMs));
  }
}

/** A fixed clock for deterministic handler tests. */
export const fixedNow = (iso = "2026-09-23T03:00:00.000Z") => () => new Date(iso);

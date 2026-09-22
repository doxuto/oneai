#!/usr/bin/env node
/**
 * v1 → v2 migration CLI. Runs against a REAL project with your credentials.
 *
 *   cd functions-v2 && npm run build
 *   gcloud auth application-default login          # once
 *   export GOOGLE_CLOUD_PROJECT=minutesai-6715a     # or oneai-staging for the dry run on a copy
 *
 *   node tools/migrate-v1.mjs inventory              # read-only counts → answers OQ-01
 *   node tools/migrate-v1.mjs plan                   # dry run, prints what would change
 *   node tools/migrate-v1.mjs plan --uid <uid>       # one user
 *   node tools/migrate-v1.mjs apply --uid <uid>      # migrate one user for real
 *   node tools/migrate-v1.mjs apply --yes            # everyone (asks for the project name first)
 *   node tools/migrate-v1.mjs apply --force ...      # re-migrate docs that already carry migratedAt
 *
 * v1 metadata/* docs are LEFT IN PLACE; the frozen v1 backend can still read
 * them during the cutover. Remove them with the sweep after v1 is retired.
 */
import { createInterface } from "node:readline/promises";
import { getApps, initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { inventory, migrateAll } from "../lib/tools/migrateV1.js";

const args = process.argv.slice(2);
const cmd = args[0];
const flag = (f) => args.includes(f);
const opt = (f) => { const i = args.indexOf(f); return i >= 0 ? args[i + 1] : undefined; };
const project = process.env.GOOGLE_CLOUD_PROJECT ?? process.env.GCLOUD_PROJECT;
if (!project) { console.error("set GOOGLE_CLOUD_PROJECT"); process.exit(2); }
if (process.env.FIRESTORE_EMULATOR_HOST) console.error(`(emulator: ${process.env.FIRESTORE_EMULATOR_HOST})`);

if (getApps().length === 0) initializeApp({ projectId: project, storageBucket: process.env.STORAGE_BUCKET ?? `${project}.firebasestorage.app` });
const db = getFirestore();
const bucket = getStorage().bucket();

if (cmd === "inventory") {
  console.log(JSON.stringify(await inventory(db), null, 2));
} else if (cmd === "plan" || cmd === "apply") {
  const dryRun = cmd === "plan";
  const uid = opt("--uid");
  if (!dryRun && !uid && !flag("--yes")) { console.error("apply for ALL users needs --yes"); process.exit(2); }
  if (!dryRun && !process.env.FIRESTORE_EMULATOR_HOST) {
    const rl = createInterface({ input: process.stdin, output: process.stdout });
    const ans = await rl.question(`About to WRITE to project "${project}"${uid ? ` for user ${uid}` : " for ALL users"}. Type the project id to continue: `);
    rl.close();
    if (ans.trim() !== project) { console.error("aborted"); process.exit(1); }
  }
  const report = await migrateAll(db, bucket, { dryRun, force: flag("--force"), log: (l) => console.log(l) }, uid);
  console.log("\n" + JSON.stringify(report, null, 2));
  if (report.warnings.length) process.exitCode = 1;
} else {
  console.error("usage: migrate-v1.mjs inventory | plan [--uid U] | apply (--uid U | --yes) [--force]");
  process.exit(2);
}

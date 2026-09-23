/**
 * The ONLY file that initializes firebase-admin.
 * firebase-functions-pro/project-layout: nothing else may call initializeApp().
 *
 * Everything is lazy so importing a handler module in a unit test does not
 * try to open a Firestore client or resolve a bucket name.
 */
import { getApps, initializeApp } from "firebase-admin/app";
import { getAuth, type Auth } from "firebase-admin/auth";
import { getFirestore, type Firestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";

function ensureApp(): void {
  if (getApps().length === 0) initializeApp();
}

let _db: Firestore | undefined;
export function getDb(): Firestore {
  if (!_db) {
    ensureApp();
    _db = getFirestore();
    _db.settings({ ignoreUndefinedProperties: true });
  }
  return _db;
}

let _auth: Auth | undefined;
export function getAdminAuth(): Auth {
  if (!_auth) {
    ensureApp();
    _auth = getAuth();
  }
  return _auth;
}

export type Bucket = ReturnType<ReturnType<typeof getStorage>["bucket"]>;
let _bucket: Bucket | undefined;
export function getBucket(): Bucket {
  if (!_bucket) {
    ensureApp();
    _bucket = getStorage().bucket();
  }
  return _bucket;
}

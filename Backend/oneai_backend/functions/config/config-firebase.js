// config/firebase.js
const admin = require('firebase-admin');
const { initializeApp, applicationDefault, cert } = require('firebase-admin/app');
const { getFirestore, Timestamp, FieldValue, Filter } = require('firebase-admin/firestore');
const { Storage } = require('@google-cloud/storage');

if (!admin.apps.length) {
  initializeApp()
}

const db = getFirestore();
const storage = new Storage({projectId: 'minutesai-6715a', keyFilename: './service-account.json'});
const bucket = storage.bucket('minutesai-6715a.firebasestorage.app');

module.exports = { db, admin, bucket, FieldValue, Timestamp };
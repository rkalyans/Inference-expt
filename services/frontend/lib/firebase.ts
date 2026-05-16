// Firebase client init. Configuration is baked at build time via
// NEXT_PUBLIC_FIREBASE_* env vars (these are not secrets — they're
// project-identifying strings that any web client would see anyway).

"use client";

import { getApp, getApps, initializeApp, type FirebaseApp } from "firebase/app";
import {
  GoogleAuthProvider,
  browserLocalPersistence,
  getAuth,
  setPersistence,
  type Auth,
} from "firebase/auth";

const cfg = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
};

export function firebaseConfigured(): boolean {
  return Boolean(cfg.apiKey && cfg.authDomain && cfg.projectId);
}

let _app: FirebaseApp | null = null;
let _auth: Auth | null = null;

export function firebaseApp(): FirebaseApp {
  if (!firebaseConfigured()) {
    throw new Error(
      "Firebase is not configured. Set NEXT_PUBLIC_FIREBASE_* env vars at build time.",
    );
  }
  if (_app) return _app;
  _app = getApps().length ? getApp() : initializeApp(cfg as Required<typeof cfg>);
  return _app;
}

export function firebaseAuth(): Auth {
  if (_auth) return _auth;
  _auth = getAuth(firebaseApp());
  // Survives reloads and the back/forward cache.
  setPersistence(_auth, browserLocalPersistence).catch(() => {});
  return _auth;
}

export const googleProvider = new GoogleAuthProvider();

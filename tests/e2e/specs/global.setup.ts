/**
 * Runs once before the authenticated projects. Signs in the provisioned test
 * user via Firebase Auth REST API (email + password), seeds Firebase's
 * localStorage record, and saves the browser context so every downstream
 * spec starts already-signed-in.
 *
 * We don't drive a real Google popup or a magic-link email. The point is to
 * exercise the bearer-token path in the agent — and that's identical
 * regardless of which provider minted the token.
 */

import { test as setup, expect } from "@playwright/test";
import { mkdirSync } from "fs";
import { env } from "../lib/env";

const STATE_PATH = "storage/authenticated.json";

setup("authenticate", async ({ page, context }) => {
  // 1. Get an ID token + refresh token from Firebase via REST.
  const signInRes = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${env.firebaseApiKey}`,
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        email: env.testEmail,
        password: env.testPassword,
        returnSecureToken: true,
      }),
    },
  );
  if (!signInRes.ok) {
    throw new Error(
      `Firebase signIn failed: ${signInRes.status} ${await signInRes.text()}`,
    );
  }
  const creds = (await signInRes.json()) as {
    idToken: string;
    refreshToken: string;
    localId: string;
    email: string;
    expiresIn: string;
  };

  // 2. Open the app — this is what fixes the localStorage origin and bootstraps
  //    the Firebase SDK so the next reload picks up our seeded user.
  await page.goto("/");

  // 3. Plant the v10 firebase-auth localStorage record. The key shape is
  //    stable across 10.x: `firebase:authUser:<apiKey>:[DEFAULT]`.
  await page.evaluate(
    ({ creds, apiKey }) => {
      const user = {
        uid: creds.localId,
        email: creds.email,
        emailVerified: true,
        isAnonymous: false,
        providerData: [
          {
            providerId: "password",
            uid: creds.email,
            displayName: null,
            email: creds.email,
            phoneNumber: null,
            photoURL: null,
          },
        ],
        stsTokenManager: {
          refreshToken: creds.refreshToken,
          accessToken: creds.idToken,
          expirationTime:
            Date.now() + Number(creds.expiresIn) * 1000,
        },
        createdAt: String(Date.now()),
        lastLoginAt: String(Date.now()),
        apiKey,
        appName: "[DEFAULT]",
      };
      const key = `firebase:authUser:${apiKey}:[DEFAULT]`;
      window.localStorage.setItem(key, JSON.stringify(user));
    },
    { creds, apiKey: env.firebaseApiKey },
  );

  // 4. Hard-navigate to a protected page. The AuthProvider should see the
  //    seeded user, fetch /api/users/me, and not redirect us to /login.
  await page.goto("/wardrobe");
  await expect(page).toHaveURL(/\/wardrobe(\?.*)?$/, { timeout: 15_000 });
  // Header user menu is the canonical "signed in" indicator.
  await expect(page.getByRole("button", { name: /sign out/i })).toBeVisible({
    timeout: 15_000,
  });

  // 5. Persist.
  mkdirSync("storage", { recursive: true });
  await context.storageState({ path: STATE_PATH });
});

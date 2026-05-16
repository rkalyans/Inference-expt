/**
 * Auth gating: unauthenticated visitors are bounced to /login, and the
 * landing page renders without requiring sign-in.
 *
 * This spec deliberately starts WITHOUT the shared authenticated storage
 * state, so it lives in its own Playwright project.
 */

import { test, expect } from "@playwright/test";

test.use({ storageState: { cookies: [], origins: [] } });

test("landing page is public", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("link", { name: /sign in/i })).toBeVisible();
  await expect(page.getByText(/pick your outfit/i)).toBeVisible();
});

test("/wardrobe redirects to /login when signed out", async ({ page }) => {
  await page.goto("/wardrobe");
  await expect(page).toHaveURL(/\/login\?next=%2Fwardrobe/);
  await expect(
    page.getByRole("heading", { name: /sign in/i }),
  ).toBeVisible();
});

test("/chat redirects to /login when signed out", async ({ page }) => {
  await page.goto("/chat");
  await expect(page).toHaveURL(/\/login\?next=%2Fchat/);
});

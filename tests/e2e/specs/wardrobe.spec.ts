/**
 * Wardrobe CRUD via the UI. We deliberately use a unique item name per run so
 * parallel/retried runs don't collide.
 */

import { test, expect } from "@playwright/test";

test("add then delete an item", async ({ page }) => {
  await page.goto("/wardrobe");
  // Page should load without redirecting away.
  await expect(page).toHaveURL(/\/wardrobe(\?.*)?$/);

  const itemName = `e2e-${Date.now().toString(36)}-${Math.random()
    .toString(36)
    .slice(2, 7)}`;

  await page.getByRole("button", { name: /add item/i }).click();
  await page.getByLabel(/name/i).fill(itemName);
  // Pick a deterministic category.
  await page.getByRole("button", { name: /^bottom$/i }).first().click();
  await page.getByRole("button", { name: /^save$/i }).click();

  // Card with the freshly-added name should appear in the grid.
  const card = page.getByText(itemName, { exact: false });
  await expect(card).toBeVisible({ timeout: 15_000 });

  // Hover to reveal delete, then click.
  await card.hover();
  await card
    .locator("xpath=ancestor::article")
    .getByRole("button", { name: /delete/i })
    .click();

  await expect(card).toHaveCount(0, { timeout: 10_000 });
});

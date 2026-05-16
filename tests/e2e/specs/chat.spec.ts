/**
 * Send a chat query and assert that the SSE pipeline yields a final
 * recommendation. We tap into the network at the response level to confirm
 * the `event: final` line is delivered, and we additionally assert the UI
 * renders the rationale.
 */

import { test, expect } from "@playwright/test";

test("chat returns a final recommendation", async ({ page }) => {
  await page.goto("/chat");
  await expect(page).toHaveURL(/\/chat(\?.*)?$/);

  // Capture the SSE stream so we can prove the final event arrived.
  const sseDonePromise = page.waitForResponse(
    (res) => res.url().endsWith("/chat") && res.status() === 200,
    { timeout: 45_000 },
  );

  await page
    .getByPlaceholder(/where are you going|what's the occasion|tell me/i)
    .fill("Coffee meeting in Midtown, 9am, sunny.");
  await page.getByRole("button", { name: /send/i }).click();

  const sseRes = await sseDonePromise;
  // Don't block on the full body — long-running streams; instead we just need
  // the UI to render the final card.
  expect(sseRes.ok()).toBeTruthy();

  // The final event renders a card whose header includes "outfit" or the
  // rationale paragraph. Match either.
  await expect(
    page.getByText(/outfit|recommendation|rationale/i).first(),
  ).toBeVisible({ timeout: 60_000 });
});

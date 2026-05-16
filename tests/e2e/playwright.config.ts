import { defineConfig, devices } from "@playwright/test";

/**
 * Configuration.
 *
 * We run the full suite against a real deployed environment (default: dev).
 * A "setup" project runs once, signs in with a provisioned test account via
 * Firebase REST API, and saves the resulting storage state. The three feature
 * projects depend on setup and reuse that state — so every test starts
 * already-authenticated and we exercise the bearer-token path in the agent.
 */

const baseURL = process.env.E2E_BASE_URL;
if (!baseURL) {
  throw new Error(
    "E2E_BASE_URL is required (e.g. https://app-dev.quantum-23.com).",
  );
}

export default defineConfig({
  testDir: "./specs",
  fullyParallel: false, // tests share a single test account
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: 1,
  reporter: [
    ["list"],
    ["html", { outputFolder: "playwright-report", open: "never" }],
    ["junit", { outputFile: "playwright-junit.xml" }],
  ],
  timeout: 60_000, // agent cold start on Cloud Run can take ~20s
  expect: { timeout: 15_000 },
  use: {
    baseURL,
    trace: "retain-on-failure",
    video: "retain-on-failure",
    screenshot: "only-on-failure",
    ignoreHTTPSErrors: true,
  },
  projects: [
    {
      name: "setup",
      testMatch: /global\.setup\.ts/,
    },
    {
      name: "auth",
      testMatch: /auth\.spec\.ts/,
      // Auth spec deliberately starts unauthenticated.
      dependencies: [],
    },
    {
      name: "wardrobe",
      testMatch: /wardrobe\.spec\.ts/,
      dependencies: ["setup"],
      use: {
        ...devices["Desktop Chrome"],
        storageState: "storage/authenticated.json",
      },
    },
    {
      name: "chat",
      testMatch: /chat\.spec\.ts/,
      dependencies: ["setup"],
      use: {
        ...devices["Desktop Chrome"],
        storageState: "storage/authenticated.json",
      },
    },
  ],
});

// Central place for all the env vars consumed by the e2e suite.
// Fail fast so a missing value produces an obvious error up front rather than
// a confusing test failure deep in the run.

function required(name: string): string {
  const v = process.env[name];
  if (!v || !v.trim()) {
    throw new Error(`Missing required env var: ${name}`);
  }
  return v.trim();
}

export const env = {
  baseURL: required("E2E_BASE_URL"),
  agentURL: required("E2E_AGENT_URL"),
  firebaseApiKey: required("E2E_FIREBASE_API_KEY"),
  testEmail: required("E2E_TEST_EMAIL"),
  testPassword: required("E2E_TEST_PASSWORD"),
};

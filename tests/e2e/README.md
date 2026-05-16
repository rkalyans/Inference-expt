# Stylist end-to-end tests

Black-box Playwright suite that drives a real deployed environment
(`app-<env>.quantum-23.com`) through the same code paths a user would.

## What we test

| Spec | What it asserts |
| --- | --- |
| `auth.spec.ts` | landing page is public; `/wardrobe` + `/chat` redirect to `/login?next=...` when signed out |
| `wardrobe.spec.ts` | add an item via the modal, see it in the grid, delete it |
| `chat.spec.ts` | send a query, observe the SSE stream succeed, see a final recommendation render |

A separate `global.setup.ts` runs once and seeds Firebase auth state for the
authenticated specs via the Firebase Auth REST API. We don't drive Google
popups or magic-link emails — they're outside the unit of behaviour we're
trying to lock down.

## Run locally against dev

```bash
cd tests/e2e
npm install
npx playwright install --with-deps chromium

# Required env vars
export E2E_BASE_URL=https://app-dev.quantum-23.com
export E2E_AGENT_URL=https://api-dev.quantum-23.com
export E2E_FIREBASE_API_KEY=AIza...               # same as _FB_API_KEY in the frontend build
export E2E_TEST_EMAIL=e2e@stylist-dev.com         # provisioned in the dev Firebase project
export E2E_TEST_PASSWORD=...                      # rotate in Secret Manager

npm test
npm run report      # open the HTML report
```

## Provisioning the test user (one-time per env)

Firebase Auth doesn't have a public "create user without a real email" API,
so we provision via the Admin SDK once per environment:

```bash
gcloud auth application-default login
PROJECT=stylist-dev
TEST_EMAIL=e2e@stylist-dev.com
TEST_PASSWORD=$(openssl rand -base64 24)

# Push the password into Secret Manager so Cloud Build can read it.
echo -n "$TEST_PASSWORD" | gcloud secrets create e2e-test-password \
  --project=$PROJECT --data-file=-
echo -n "$TEST_EMAIL"    | gcloud secrets create e2e-test-email \
  --project=$PROJECT --data-file=-

# Then mint the user. There's a small Python helper at scripts/provision-e2e-user.py
# in this repo — or use the Firebase console.
```

## In Cloud Build

`ci/cloudbuild-e2e.yaml` runs the whole suite inside the official
`mcr.microsoft.com/playwright:v1.48.0-jammy` image (browsers preinstalled).
On failure it still uploads the HTML report to
`gs://<project>_cloudbuild/e2e/<build_id>/playwright-report.zip` so you can
download and inspect it.

Trigger it manually:

```bash
gcloud builds submit \
  --config=ci/cloudbuild-e2e.yaml \
  --substitutions=_ENV=dev,\
_BASE_URL=https://app-dev.quantum-23.com,\
_AGENT_URL=https://api-dev.quantum-23.com,\
_FB_API_KEY=AIza... .
```

In the promotion pipeline (phase 1.7) this build is set as a required
predecessor before flipping traffic to the next env.

## Why no mocks?

We're testing production wiring: Firebase issues real tokens, the agent
verifies them with real public keys, Cloud SQL stores the real row,
inventory rejects 401 calls. Mocking any of those would shrink the surface
area we're trying to protect.

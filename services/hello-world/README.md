# stylist-hello

Phase 0 smoke-test container. Single FastAPI service that returns `200` from
`/healthz` and exposes a friendly root page. Built and deployed by Cloud Build,
runs on Cloud Run, and validates the entire delivery pipeline end-to-end.

> All execution happens in **Google Cloud Shell**. There is no local-run path.

## Build & deploy via Cloud Build

```bash
# In Cloud Shell, from the repo root
cd ~/stylist-agent
gcloud builds submit --config=ci/cloudbuild-hello.yaml \
  --substitutions=_ENV=dev .
```

## Optional: run inside Cloud Shell for quick iteration

If you want to exercise the Python app without a Cloud Build round-trip, you can run it inside Cloud Shell itself (it has Python 3 + Docker):

```bash
cd ~/stylist-agent/services/hello-world
docker build -t stylist-hello .
docker run --rm -p 8080:8080 -e APP_ENV=cloudshell stylist-hello &
curl localhost:8080/healthz
```

Use Cloud Shell's **Web Preview** button (top right) on port 8080 to view the service in your browser.

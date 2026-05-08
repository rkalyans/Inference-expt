#!/usr/bin/env bash
# Seed Phase 0 secrets into Secret Manager. Reads values from environment vars
# so the script itself never sees them on disk.
#
# Required env vars (set them in your shell, do NOT commit):
#   OPENWEATHERMAP_API_KEY
#   LANGFUSE_PUBLIC_KEY    (after Langfuse is deployed; can rerun later)
#   LANGFUSE_SECRET_KEY
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-inference-expt}"

upsert_secret() {
  local name="$1" value="$2"
  if [ -z "${value:-}" ]; then
    echo "  SKIP: $name (env var not set)"
    return 0
  fi
  if ! gcloud secrets describe "$name" --project="$PROJECT_ID" >/dev/null 2>&1; then
    echo "  CREATE: $name"
    gcloud secrets create "$name" --project="$PROJECT_ID" \
      --replication-policy=automatic \
      --labels="app=stylist-agent,env=shared"
  else
    echo "  EXISTS: $name (adding new version)"
  fi
  printf '%s' "$value" | gcloud secrets versions add "$name" \
    --project="$PROJECT_ID" --data-file=-
}

echo "==> Seeding secrets in $PROJECT_ID"
upsert_secret "openweathermap-api-key" "${OPENWEATHERMAP_API_KEY:-}"
upsert_secret "langfuse-public-key"    "${LANGFUSE_PUBLIC_KEY:-}"
upsert_secret "langfuse-secret-key"    "${LANGFUSE_SECRET_KEY:-}"

# Validate OpenWeatherMap key against One Call API 3.0
if [ -n "${OPENWEATHERMAP_API_KEY:-}" ]; then
  echo "==> Validating OpenWeatherMap key (One Call API 3.0)"
  HTTP="$(curl -s -o /tmp/owm.json -w '%{http_code}' \
    "https://api.openweathermap.org/data/3.0/onecall?lat=40.7580&lon=-73.9855&exclude=minutely,alerts&appid=${OPENWEATHERMAP_API_KEY}" \
    || true)"
  if [ "$HTTP" = "200" ]; then
    echo "    OK ($HTTP) — One Call API 3.0 reachable."
  else
    echo "    WARN: HTTP $HTTP. Response:"
    cat /tmp/owm.json || true
    echo
    echo "    Confirm subscription includes One Call API 3.0."
  fi
  rm -f /tmp/owm.json
fi

#!/usr/bin/env bash
# db-migrate: runs Cloud SQL Auth Proxy + applies SQL files in /app/migrations.
# Designed to run as a Cloud Run Job with a serverless VPC connector so it can
# reach Cloud SQL on its private IP. Uses IAM authentication when DB_USER is a
# service-account email; falls back to password auth from Secret Manager.
#
# Required env (passed by Terraform / Cloud Run Job spec):
#   PROJECT_ID    e.g. inference-expt
#   ENV           dev|staging|prod
#   REGION        e.g. us-east4
#   DB_NAME       default: stylist
#   USE_IAM_AUTH  "true"|"false" (default true)

set -euo pipefail

: "${PROJECT_ID:?PROJECT_ID is required}"
: "${ENV:?ENV is required}"
: "${REGION:?REGION is required}"
DB_NAME="${DB_NAME:-stylist}"
USE_IAM_AUTH="${USE_IAM_AUTH:-true}"

INSTANCE="${PROJECT_ID}:${REGION}:stylist-${ENV}-pg"
echo "===== Starting Cloud SQL Auth Proxy for ${INSTANCE} ====="

if [ "${USE_IAM_AUTH}" = "true" ]; then
  cloud-sql-proxy --private-ip --auto-iam-authn --port=5432 "${INSTANCE}" &
else
  cloud-sql-proxy --private-ip --port=5432 "${INSTANCE}" &
fi
PROXY_PID=$!
trap 'kill ${PROXY_PID} 2>/dev/null || true' EXIT

for i in $(seq 1 30); do
  if pg_isready -h 127.0.0.1 -p 5432 -q; then echo "proxy ready"; break; fi
  sleep 1
done

# Fetch an OAuth token from the GCE metadata server. Works on Cloud Run, GCE,
# GKE — anywhere a Google-issued workload identity exists. Avoids gcloud.
METADATA_BASE="http://metadata.google.internal/computeMetadata/v1"
METADATA_HDR="Metadata-Flavor: Google"

fetch_metadata() {
  curl -fsS -H "${METADATA_HDR}" "${METADATA_BASE}/$1"
}

fetch_access_token() {
  fetch_metadata "instance/service-accounts/default/token" | jq -r '.access_token'
}

# Read the latest version of a Secret Manager secret via REST.
# Args: $1 = secret_id
fetch_secret() {
  local secret_id="$1"
  local token
  token=$(fetch_access_token)
  curl -fsS \
    -H "Authorization: Bearer ${token}" \
    "https://secretmanager.googleapis.com/v1/projects/${PROJECT_ID}/secrets/${secret_id}/versions/latest:access" \
    | jq -r '.payload.data' \
    | base64 -d
}

if [ "${USE_IAM_AUTH}" = "true" ]; then
  # IAM authentication — connect as the runtime service account itself.
  # Postgres truncates IAM usernames at 63 chars and strips the `.gserviceaccount.com`
  # suffix; do it explicitly so we don't depend on Postgres heuristics.
  PGUSER=$(fetch_metadata "instance/service-accounts/default/email")
  PGUSER="${PGUSER%.gserviceaccount.com}"
  export PGUSER
  unset PGPASSWORD
else
  # Bootstrap (password) authentication — used on the very first migration so
  # the IAM user can be granted privileges. Switch to USE_IAM_AUTH=true after.
  export PGUSER="stylist-root"
  PGPASSWORD=$(fetch_secret "stylist-${ENV}-pg-root-password")
  export PGPASSWORD
fi

export PGHOST=127.0.0.1
export PGPORT=5432
export PGDATABASE="${DB_NAME}"

echo "===== Connecting as ${PGUSER} to ${PGDATABASE} ====="
psql -tAc 'SELECT version FROM schema_migrations ORDER BY version' 2>/dev/null \
  || echo '(schema_migrations not yet created — first migration will create it)'

echo "===== Applying migrations in lexical order ====="
for f in $(ls /app/migrations/*.sql | sort); do
  echo "----- ${f} -----"
  psql -v ON_ERROR_STOP=1 -f "${f}"
done

echo "===== Final state of schema_migrations ====="
psql -c 'SELECT version, applied_at FROM schema_migrations ORDER BY version'

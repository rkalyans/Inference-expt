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

if [ "${USE_IAM_AUTH}" = "true" ]; then
  PGUSER="$(gcloud config list account --format='value(core.account)' 2>/dev/null || true)"
  if [ -z "${PGUSER}" ]; then
    # Running on Cloud Run — fetch the runtime SA email from metadata.
    PGUSER=$(curl -s -H 'Metadata-Flavor: Google' \
      http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email)
  fi
  PGUSER="${PGUSER%.gserviceaccount.com}"
  export PGUSER
  unset PGPASSWORD
else
  export PGUSER="stylist-root"
  PGPASSWORD=$(gcloud secrets versions access latest \
    --secret="stylist-${ENV}-pg-root-password" --project="${PROJECT_ID}")
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

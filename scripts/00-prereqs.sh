#!/usr/bin/env bash
# Verify Phase 0 prerequisites. Designed to run inside Google Cloud Shell.
# If $CLOUD_SHELL=true (set by Cloud Shell automatically), CLI install
# checks are treated as informational only.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-inference-expt}"
BILLING_ACCOUNT_NAME="${BILLING_ACCOUNT_NAME:-Billing-Account-Agentic}"
DOMAIN="${DOMAIN:-quantum-23.com}"

echo "==> Phase 0 prerequisite check"
echo "    PROJECT_ID = $PROJECT_ID"
echo "    BILLING    = $BILLING_ACCOUNT_NAME"
echo "    DOMAIN     = $DOMAIN"

if [ "${CLOUD_SHELL:-false}" = "true" ]; then
  echo "    ENV        = Google Cloud Shell (recommended)"
else
  echo "    ENV        = NOT Cloud Shell — please run this from https://shell.cloud.google.com"
  echo "                 (Phase 0 is designed to be executed entirely in Cloud Shell.)"
fi
echo

fail() { echo "ERROR: $*" >&2; exit 1; }

# Required CLIs (guaranteed in Cloud Shell, but verify anyway)
command -v gcloud    >/dev/null || fail "gcloud missing (Cloud Shell should provide it)"
command -v terraform >/dev/null || fail "terraform missing (Cloud Shell should provide it)"
command -v jq        >/dev/null || fail "jq missing"
command -v docker    >/dev/null || fail "docker missing"

# Terraform version
TF_VER="$(terraform version -json | jq -r '.terraform_version')"
echo "==> Terraform version: $TF_VER"

# Active gcloud account (Cloud Shell pre-authenticates)
ACTIVE_ACCOUNT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' || true)"
[ -n "$ACTIVE_ACCOUNT" ] || fail "No active gcloud account. In Cloud Shell, run: gcloud auth login"
echo "==> Active gcloud account: $ACTIVE_ACCOUNT"

# Application Default Credentials (Cloud Shell provides via metadata server)
gcloud auth application-default print-access-token >/dev/null 2>&1 || \
  fail "ADC not available. Open a fresh Cloud Shell tab, or run: gcloud auth application-default login"

# Project exists & is active
gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1 || \
  fail "Project '$PROJECT_ID' not found or not accessible by $ACTIVE_ACCOUNT"

CURRENT_PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
if [ "$CURRENT_PROJECT" != "$PROJECT_ID" ]; then
  echo "==> Setting active project to $PROJECT_ID"
  gcloud config set project "$PROJECT_ID"
fi

# Billing
BILLING_INFO="$(gcloud billing projects describe "$PROJECT_ID" --format=json 2>/dev/null || echo '{}')"
BILLING_ENABLED="$(echo "$BILLING_INFO" | jq -r '.billingEnabled // false')"
[ "$BILLING_ENABLED" = "true" ] || fail "Billing not enabled on $PROJECT_ID. Link account '$BILLING_ACCOUNT_NAME'."
echo "==> Billing enabled on $PROJECT_ID"

echo
echo "All prerequisites satisfied."

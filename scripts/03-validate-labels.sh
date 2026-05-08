#!/usr/bin/env bash
# CI guard: ensure every "stylist-*" resource carries env + app labels.
# Returns non-zero if any resource is missing the required labels.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-inference-expt}"
REQUIRED_LABELS=("env" "app")
EXPECTED_APP="stylist-agent"

fail=0
echo "==> Validating mandatory labels on stylist-* resources in $PROJECT_ID"

check_resource() {
  local kind="$1" name="$2" labels_json="$3"
  for key in "${REQUIRED_LABELS[@]}"; do
    val="$(echo "$labels_json" | jq -r --arg k "$key" '.[$k] // empty')"
    if [ -z "$val" ]; then
      echo "  [MISSING] $kind/$name missing label '$key'"
      fail=1
    fi
  done
  app_val="$(echo "$labels_json" | jq -r '.app // empty')"
  if [ -n "$app_val" ] && [ "$app_val" != "$EXPECTED_APP" ]; then
    echo "  [WRONG]   $kind/$name has app=$app_val (expected $EXPECTED_APP)"
    fail=1
  fi
}

# Cloud Run services
echo "--> Cloud Run services"
gcloud run services list --project="$PROJECT_ID" \
  --filter="metadata.name~^stylist-" \
  --format="json" 2>/dev/null | \
  jq -c '.[] | {name: .metadata.name, labels: (.metadata.labels // {})}' | \
  while read -r row; do
    name="$(echo "$row" | jq -r '.name')"
    labels="$(echo "$row" | jq -c '.labels')"
    check_resource "cloud-run" "$name" "$labels"
  done

# GCS buckets
echo "--> GCS buckets"
gcloud storage buckets list --project="$PROJECT_ID" \
  --filter="name~^stylist-" --format=json 2>/dev/null | \
  jq -c '.[] | {name: .name, labels: (.labels // {})}' | \
  while read -r row; do
    name="$(echo "$row" | jq -r '.name')"
    labels="$(echo "$row" | jq -c '.labels')"
    check_resource "gcs" "$name" "$labels"
  done

# Service accounts (labels-via-description fallback isn't great; skip but warn)
echo "--> (Service accounts and DNS records skipped — labels not natively supported)"

if [ "$fail" -ne 0 ]; then
  echo
  echo "FAIL: One or more resources are missing mandatory labels."
  exit 1
fi
echo
echo "PASS: All stylist-* resources have the required labels."

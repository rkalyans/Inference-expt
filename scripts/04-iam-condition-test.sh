#!/usr/bin/env bash
# Verify IAM Conditions: dev SA cannot read prod-labeled resources.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-inference-expt}"
DEV_SA="agent-orch-dev-sa@${PROJECT_ID}.iam.gserviceaccount.com"
PROD_BUCKET="gs://stylist-prod-clothing-photos"

echo "==> IAM Condition smoke test"
echo "    SA            = $DEV_SA"
echo "    Probe target  = $PROD_BUCKET (should be DENIED)"

# Impersonate the dev SA and try to list prod bucket
set +e
OUTPUT="$(gcloud storage ls "$PROD_BUCKET" \
  --impersonate-service-account="$DEV_SA" 2>&1)"
RC=$?
set -e

if [ $RC -ne 0 ] && echo "$OUTPUT" | grep -qiE "permission|denied|forbidden|403"; then
  echo "PASS: dev SA correctly denied access to prod bucket."
  exit 0
fi

echo "FAIL: dev SA was able to access prod bucket (or unexpected error):"
echo "$OUTPUT"
exit 1

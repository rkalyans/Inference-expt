#!/usr/bin/env bash
# Create the one-time Terraform state bucket. Idempotent.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-inference-expt}"
REGION="${REGION:-us-east4}"
BUCKET="gs://${PROJECT_ID}-tf-state"

echo "==> Bootstrapping Terraform state bucket: $BUCKET"

if gcloud storage buckets describe "$BUCKET" >/dev/null 2>&1; then
  echo "    Bucket already exists. Skipping create."
else
  gcloud storage buckets create "$BUCKET" \
    --project="$PROJECT_ID" \
    --location="$REGION" \
    --uniform-bucket-level-access \
    --public-access-prevention
  echo "    Bucket created."
fi

echo "==> Enabling versioning"
gcloud storage buckets update "$BUCKET" --versioning

echo "==> Setting lifecycle (delete noncurrent versions > 90 days)"
TMP_LIFECYCLE="$(mktemp)"
cat > "$TMP_LIFECYCLE" <<'EOF'
{
  "lifecycle": {
    "rule": [
      {
        "action": {"type": "Delete"},
        "condition": {"daysSinceNoncurrentTime": 90}
      }
    ]
  }
}
EOF
gcloud storage buckets update "$BUCKET" --lifecycle-file="$TMP_LIFECYCLE"
rm -f "$TMP_LIFECYCLE"

echo
echo "State bucket ready: $BUCKET"

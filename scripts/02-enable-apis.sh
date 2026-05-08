#!/usr/bin/env bash
# Enable all Phase 0 + future-phase APIs on the project. Idempotent.
set -euo pipefail

PROJECT_ID="${PROJECT_ID:-inference-expt}"

APIS=(
  # Compute / runtime
  run.googleapis.com
  container.googleapis.com
  cloudfunctions.googleapis.com
  cloudscheduler.googleapis.com
  pubsub.googleapis.com

  # Data
  sqladmin.googleapis.com
  firestore.googleapis.com
  storage.googleapis.com
  bigquery.googleapis.com
  redis.googleapis.com

  # Networking / DNS
  compute.googleapis.com
  dns.googleapis.com
  servicenetworking.googleapis.com
  vpcaccess.googleapis.com

  # CI/CD & registry
  cloudbuild.googleapis.com
  artifactregistry.googleapis.com

  # Security / identity / governance
  secretmanager.googleapis.com
  iam.googleapis.com
  iamcredentials.googleapis.com
  cloudresourcemanager.googleapis.com
  serviceusage.googleapis.com
  dlp.googleapis.com
  cloudkms.googleapis.com

  # Observability
  logging.googleapis.com
  monitoring.googleapis.com
  cloudtrace.googleapis.com
  cloudprofiler.googleapis.com

  # Billing
  cloudbilling.googleapis.com
  billingbudgets.googleapis.com

  # AI (for later phases — enabled now to avoid surprises)
  aiplatform.googleapis.com
)

echo "==> Enabling ${#APIS[@]} APIs on $PROJECT_ID (this can take a few minutes)"
gcloud services enable "${APIS[@]}" --project="$PROJECT_ID"
echo "==> Done."

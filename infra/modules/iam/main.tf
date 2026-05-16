/**
 * IAM module — creates service accounts only.
 *
 * Permissions philosophy:
 *   • Project-level roles are granted ONLY to admin SAs (terraform-sa,
 *     cloudbuild-sa) where unavoidable.
 *   • Per-env runtime SAs are granted permissions at the *resource level*
 *     by the modules that own those resources (e.g. a GCS bucket grants
 *     objectAdmin to its env's SA only).
 *   • This guarantees that agent-orch-dev-sa cannot touch prod resources
 *     because no binding exists — verifiable via the impersonation test in
 *     PHASE-0-RUNBOOK.md §10.3.
 *
 * Resource Tags (env=dev|staging|prod) are also created here for any future
 * IAM Condition use cases or VPC-SC perimeter scoping.
 */

locals {
  is_shared = var.env == "shared"
  is_runtime = var.env != "shared"
}

# ----- Cloud Build SA (shared only) -----
resource "google_service_account" "cloudbuild" {
  count        = local.is_shared ? 1 : 0
  project      = var.project_id
  account_id   = "cloudbuild-sa"
  display_name = "Cloud Build CI/CD"
  description  = "Used by Cloud Build to deploy across all envs"
}

resource "google_project_iam_member" "cloudbuild_roles" {
  for_each = local.is_shared ? toset([
    "roles/run.admin",
    "roles/artifactregistry.writer",
    "roles/iam.serviceAccountUser",
    "roles/cloudbuild.builds.builder",
    "roles/storage.admin",
    "roles/secretmanager.secretAccessor",
    "roles/logging.logWriter",
    "roles/cloudsql.client",      # for cloudbuild-migrate.yaml
    "roles/cloudsql.instanceUser",
  ]) : []

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.cloudbuild[0].email}"
}

# ----- Terraform SA (shared only) -----
resource "google_service_account" "terraform" {
  count        = local.is_shared ? 1 : 0
  project      = var.project_id
  account_id   = "terraform-sa"
  display_name = "Terraform CI"
}

resource "google_project_iam_member" "terraform_roles" {
  for_each = local.is_shared ? toset([
    "roles/editor",
    "roles/resourcemanager.projectIamAdmin",
    "roles/iam.serviceAccountAdmin",
    "roles/dns.admin",
    # NOTE: roles/billing.user is a billing-account-level role, not project-level.
    # If you need terraform-sa to create budgets, grant it at the billing account:
    #   gcloud billing accounts add-iam-policy-binding $BILLING_ACCOUNT_ID \
    #     --member="serviceAccount:terraform-sa@inference-expt.iam.gserviceaccount.com" \
    #     --role="roles/billing.user"
    # In Phase 0 the human owner runs `terraform apply` directly, so this is unnecessary.
  ]) : []

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.terraform[0].email}"
}

# ----- Per-env runtime SAs -----
# These are granted permissions ONLY at the resource level by other modules.
# No project-level bindings here — that's the safety property.

resource "google_service_account" "agent_orchestrator" {
  count        = local.is_runtime ? 1 : 0
  project      = var.project_id
  account_id   = "agent-orch-${var.env}-sa"
  display_name = "Agent Orchestrator (${var.env})"
}

resource "google_service_account" "inference" {
  count        = local.is_runtime ? 1 : 0
  project      = var.project_id
  account_id   = "inference-${var.env}-sa"
  display_name = "GKE Inference (${var.env})"
}

resource "google_service_account" "street_feed" {
  count        = local.is_runtime ? 1 : 0
  project      = var.project_id
  account_id   = "street-feed-${var.env}-sa"
  display_name = "Street Feed Worker (${var.env})"
}

# Per-env runtime SAs need basic logging/monitoring writer rights project-wide.
# These are the only project-level grants for runtime SAs.
resource "google_project_iam_member" "runtime_telemetry" {
  for_each = local.is_runtime ? toset([
    "roles/logging.logWriter",
    "roles/monitoring.metricWriter",
    "roles/cloudtrace.agent",
  ]) : []

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.agent_orchestrator[0].email}"
}

# ----- Resource Tags (for VPC-SC, future IAM conditions, audit clarity) -----
resource "google_tags_tag_key" "env" {
  count       = local.is_shared ? 1 : 0
  parent      = "projects/${var.project_id}"
  short_name  = "env"
  description = "Environment classification (dev|staging|prod|shared)"
}

resource "google_tags_tag_value" "env_values" {
  for_each = local.is_shared ? toset(["dev", "staging", "prod", "shared"]) : []

  parent     = google_tags_tag_key.env[0].id
  short_name = each.value
}

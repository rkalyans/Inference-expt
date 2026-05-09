/**
 * Shared stack — project-wide foundation.
 *
 * Creates: VPC + subnets, DNS zones, Artifact Registry, IAM SAs,
 * Secret Manager placeholders, ops analytics + budgets + Langfuse.
 *
 * Apply this BEFORE any env stack.
 */

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.40"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  common_labels = {
    app = "stylist-agent"
    env = "shared"
  }
}

# ----- Network -----
module "network" {
  source     = "../../modules/network"
  project_id = var.project_id
  region     = var.region
}

# ----- DNS -----
module "dns" {
  source        = "../../modules/dns"
  project_id    = var.project_id
  domain        = var.domain
  vpc_self_link = module.network.vpc_self_link
  labels        = local.common_labels
}

# ----- Artifact Registry -----
module "artifact_registry" {
  source     = "../../modules/artifact-registry"
  project_id = var.project_id
  region     = var.region
  labels     = local.common_labels
}

# ----- IAM (CI service accounts + tag keys) -----
module "iam_shared" {
  source     = "../../modules/iam"
  project_id = var.project_id
  env        = "shared"
}

# ----- Secrets (placeholders; values added manually per PHASE-0-RUNBOOK.md §6) -----
module "secrets" {
  source     = "../../modules/secrets"
  project_id = var.project_id

  secret_names = [
    "openweathermap-api-key",
    "langfuse-public-key",
    "langfuse-secret-key",
    "langfuse-database-url",
    "langfuse-nextauth-secret",
    "langfuse-salt",
  ]

  labels = local.common_labels
}

# ----- Service account for Langfuse Cloud Run -----
resource "google_service_account" "langfuse" {
  project      = var.project_id
  account_id   = "stylist-langfuse-sa"
  display_name = "Langfuse Cloud Run"
}

resource "google_project_iam_member" "langfuse_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.langfuse.email}"
}

resource "google_project_iam_member" "langfuse_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.langfuse.email}"
}

# ----- Observability (budgets, log sinks, alert policies, Langfuse) -----
module "observability" {
  source             = "../../modules/observability"
  project_id         = var.project_id
  region             = var.region
  billing_account_id = var.billing_account_id
  owner_email        = var.owner_email
  domain             = var.domain
  langfuse_sa_email  = google_service_account.langfuse.email
  deploy_langfuse    = var.deploy_langfuse

  budgets = {
    dev     = "100"
    staging = "200"
    prod    = "500"
  }

  labels = local.common_labels

  depends_on = [module.secrets]
}

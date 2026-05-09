/**
 * Shared stack — project-wide foundation.
 *
 * Creates: VPC + subnets, DNS zones, Artifact Registry, IAM SAs,
 * Secret Manager placeholders, ops analytics + budgets.
 *
 * Observability backend is Langfuse Cloud (SaaS) — we only store the three
 * client credentials in Secret Manager. No self-hosted Langfuse server.
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
    # Langfuse Cloud (SaaS) client credentials — paste from
    # https://cloud.langfuse.com → Settings → API Keys
    "langfuse-public-key",
    "langfuse-secret-key",
    "langfuse-host",
  ]

  labels = local.common_labels
}

# ----- Observability (budgets, log sinks, alert policies) -----
# Langfuse runs as SaaS (cloud.langfuse.com); not deployed here.
module "observability" {
  source             = "../../modules/observability"
  project_id         = var.project_id
  region             = var.region
  billing_account_id = var.billing_account_id
  owner_email        = var.owner_email

  budgets = {
    dev     = "100"
    staging = "200"
    prod    = "500"
  }

  labels = local.common_labels

  depends_on = [module.secrets]
}

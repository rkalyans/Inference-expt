/**
 * Dev stack — env-scoped resources within inference-expt.
 * Phase 0 deploys a single hello-world Cloud Run service to validate
 * end-to-end CI/CD + DNS + IAM.
 */

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.40" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Read shared stack outputs
data "terraform_remote_state" "shared" {
  backend = "gcs"
  config = {
    bucket = "inference-expt-tf-state"
    prefix = "shared"
  }
}

locals {
  env = "dev"
  common_labels = {
    app = "stylist-agent"
    env = local.env
  }
}

# ----- Per-env service accounts -----
module "iam_dev" {
  source     = "../../modules/iam"
  project_id = var.project_id
  env        = local.env
}

# ----- GCS buckets (env-scoped, even if empty in Phase 0) -----
resource "google_storage_bucket" "clothing_photos" {
  name                        = "stylist-${local.env}-clothing-photos"
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = local.env == "dev"

  versioning { enabled = true }

  labels = local.common_labels
}

resource "google_storage_bucket" "agent_sessions" {
  name                        = "stylist-${local.env}-agent-sessions"
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = local.env == "dev"

  lifecycle_rule {
    condition { age = 30 }
    action    { type = "Delete" }
  }

  labels = local.common_labels
}

# Resource-level binding: agent-orch-dev-sa can ONLY access dev buckets.
# This is the safety property that 04-iam-condition-test.sh validates.
resource "google_storage_bucket_iam_member" "agent_orch_clothing" {
  bucket = google_storage_bucket.clothing_photos.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${module.iam_dev.agent_orchestrator_sa_email}"
}

resource "google_storage_bucket_iam_member" "agent_orch_sessions" {
  bucket = google_storage_bucket.agent_sessions.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${module.iam_dev.agent_orchestrator_sa_email}"
}

# ----- Hello-world smoke-test service -----
module "hello_world" {
  source = "../../modules/cloud-run-service"

  project_id            = var.project_id
  region                = var.region
  name                  = "stylist-${local.env}-hello"
  image                 = var.hello_image
  service_account_email = module.iam_dev.agent_orchestrator_sa_email

  min_instances = 0
  max_instances = 3
  cpu           = "1"
  memory        = "512Mi"

  env_vars = {
    APP_ENV  = local.env
    APP_NAME = "stylist-hello"
  }

  allow_public  = true
  dns_subdomain = local.env # dev.quantum-23.com
  domain        = var.domain
  dns_zone_name = data.terraform_remote_state.shared.outputs.dns_zone_name

  labels = local.common_labels

  depends_on = [data.terraform_remote_state.shared]
}

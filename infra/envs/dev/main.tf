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

resource "google_storage_bucket" "model_weights" {
  name                        = "stylist-${local.env}-model-weights"
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = local.env == "dev"
  versioning { enabled = true }
  labels = local.common_labels
}

resource "google_storage_bucket" "street_feed_frames" {
  name                        = "stylist-${local.env}-street-feed-frames"
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = local.env == "dev"

  # 24h frame retention enforces the no-PII data scope (DEPLOYMENT-PLAN §3.6)
  lifecycle_rule {
    condition { age = 1 }
    action    { type = "Delete" }
  }

  labels = local.common_labels
}

# Resource-level binding: agent-orch-dev-sa can ONLY access dev buckets.
# This is the safety property that the IAM condition test validates.
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

resource "google_storage_bucket_iam_member" "agent_orch_model_weights_read" {
  bucket = google_storage_bucket.model_weights.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${module.iam_dev.agent_orchestrator_sa_email}"
}

resource "google_storage_bucket_iam_member" "agent_orch_street_frames" {
  bucket = google_storage_bucket.street_feed_frames.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${module.iam_dev.agent_orchestrator_sa_email}"
}

# ===== Phase 1.1 Data Layer =====

module "cloud_sql" {
  source         = "../../modules/cloud-sql"
  project_id     = var.project_id
  region         = var.region
  env            = local.env
  vpc_self_link  = data.terraform_remote_state.shared.outputs.vpc_self_link
  tier           = "db-f1-micro"
  disk_size_gb   = 20
  iam_user_email = module.iam_dev.agent_orchestrator_sa_email
  labels         = local.common_labels

  # Don't try to create Cloud SQL until PSA peering exists
  depends_on = [data.terraform_remote_state.shared]
}

module "firestore" {
  source     = "../../modules/firestore"
  project_id = var.project_id
  env        = local.env
  location   = var.region
}

module "memorystore" {
  source         = "../../modules/memorystore"
  project_id     = var.project_id
  region         = var.region
  env            = local.env
  vpc_id         = data.terraform_remote_state.shared.outputs.vpc_self_link
  memory_size_gb = 1
  labels         = local.common_labels
}

module "bigquery" {
  source     = "../../modules/bigquery"
  project_id = var.project_id
  env        = local.env
  location   = var.region
  labels     = local.common_labels
}

# Runtime IAM for the agent orchestrator SA to use the data layer.
locals {
  agent_orch_member = "serviceAccount:${module.iam_dev.agent_orchestrator_sa_email}"
}

resource "google_project_iam_member" "agent_orch_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = local.agent_orch_member
  condition {
    title      = "only-${local.env}-cloudsql"
    expression = "resource.name.startsWith(\"projects/${var.project_id}/instances/stylist-${local.env}-pg\")"
  }
}

resource "google_project_iam_member" "agent_orch_cloudsql_instance_user" {
  project = var.project_id
  role    = "roles/cloudsql.instanceUser"
  member  = local.agent_orch_member
  condition {
    title      = "only-${local.env}-cloudsql"
    expression = "resource.name.startsWith(\"projects/${var.project_id}/instances/stylist-${local.env}-pg\")"
  }
}

resource "google_project_iam_member" "agent_orch_firestore_user" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = local.agent_orch_member
  condition {
    title      = "only-${local.env}-firestore"
    expression = "resource.name.endsWith(\"/databases/stylist-${local.env}\")"
  }
}

resource "google_project_iam_member" "agent_orch_redis_editor" {
  project = var.project_id
  role    = "roles/redis.editor"
  member  = local.agent_orch_member
  condition {
    title      = "only-${local.env}-redis"
    expression = "resource.name.endsWith(\"/instances/stylist-${local.env}-redis\")"
  }
}

resource "google_project_iam_member" "agent_orch_bq_data_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = local.agent_orch_member
  condition {
    title      = "only-${local.env}-bq-datasets"
    expression = "resource.name.startsWith(\"projects/${var.project_id}/datasets/stylist_${local.env}_\")"
  }
}

resource "google_project_iam_member" "agent_orch_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = local.agent_orch_member
}

# Dedicated SA for the db-migrate Cloud Run Job so we can grant Cloud SQL
# IAM-auth + Secret Manager rights without bloating the agent SA.
resource "google_service_account" "db_migrate" {
  project      = var.project_id
  account_id   = "db-migrate-${local.env}-sa"
  display_name = "db-migrate (${local.env})"
}

locals {
  db_migrate_member = "serviceAccount:${google_service_account.db_migrate.email}"
}

resource "google_sql_user" "db_migrate_iam" {
  project  = var.project_id
  instance = module.cloud_sql.instance_name
  name     = trimsuffix(google_service_account.db_migrate.email, ".gserviceaccount.com")
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

resource "google_project_iam_member" "db_migrate_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = local.db_migrate_member
  condition {
    title      = "only-${local.env}-cloudsql"
    expression = "resource.name.startsWith(\"projects/${var.project_id}/instances/stylist-${local.env}-pg\")"
  }
}

resource "google_project_iam_member" "db_migrate_cloudsql_instance_user" {
  project = var.project_id
  role    = "roles/cloudsql.instanceUser"
  member  = local.db_migrate_member
  condition {
    title      = "only-${local.env}-cloudsql"
    expression = "resource.name.startsWith(\"projects/${var.project_id}/instances/stylist-${local.env}-pg\")"
  }
}

resource "google_secret_manager_secret_iam_member" "db_migrate_root_pw" {
  project   = var.project_id
  secret_id = module.cloud_sql.root_password_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.db_migrate_member
}

# Bootstrap: grant the IAM user inside Postgres permission to create everything.
# After the first migration runs, the schema_migrations row will exist and
# subsequent runs are no-ops.
resource "google_project_iam_member" "db_migrate_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = local.db_migrate_member
}

module "db_migrate_job" {
  source                = "../../modules/cloud-run-job"
  project_id            = var.project_id
  region                = var.region
  name                  = "stylist-${local.env}-db-migrate"
  image                 = var.migrate_image
  service_account_email = google_service_account.db_migrate.email
  vpc_connector_id      = data.terraform_remote_state.shared.outputs.vpc_connector_id

  env_vars = {
    PROJECT_ID = var.project_id
    ENV        = local.env
    REGION     = var.region
    DB_NAME    = "stylist"
    # Force password auth on first run because the IAM user we just created
    # has no schema privileges yet. Switch to "true" after first successful migration.
    USE_IAM_AUTH = "false"
  }

  labels = local.common_labels
}

# ============================================================
# Phase 1.2 — GKE inference cluster
# ============================================================

module "gke" {
  source = "../../modules/gke"

  project_id          = var.project_id
  region              = var.region
  env                 = local.env
  vpc_self_link       = data.terraform_remote_state.shared.outputs.vpc_self_link
  subnet_self_link    = data.terraform_remote_state.shared.outputs.subnets[local.env].self_link
  pods_range_name     = data.terraform_remote_state.shared.outputs.subnets[local.env].pods_range
  services_range_name = data.terraform_remote_state.shared.outputs.subnets[local.env].services_range
  master_cidr         = data.terraform_remote_state.shared.outputs.subnets[local.env].master_cidr

  # Dev: zero GPU floor; one GPU node max to keep idle cost zero.
  cpu_min_nodes = 1
  cpu_max_nodes = 2
  gpu_min_nodes = 0
  gpu_max_nodes = 1

  deletion_protection = false
  labels              = local.common_labels
}

# ============================================================
# Phase 1.3 — Backend services (weather, inventory, agent)
# ============================================================

# ----- weather service account + per-resource IAM -----
resource "google_service_account" "weather" {
  project      = var.project_id
  account_id   = "weather-${local.env}-sa"
  display_name = "Weather Tool (${local.env})"
}

locals {
  weather_member = "serviceAccount:${google_service_account.weather.email}"
}

resource "google_project_iam_member" "weather_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = local.weather_member
}

resource "google_secret_manager_secret_iam_member" "weather_owm_key" {
  project   = var.project_id
  secret_id = "openweathermap-api-key" # created out-of-band; see runbook
  role      = "roles/secretmanager.secretAccessor"
  member    = local.weather_member
}

resource "google_secret_manager_secret_iam_member" "weather_redis_auth" {
  project   = var.project_id
  secret_id = module.memorystore.auth_secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = local.weather_member
}

# ----- inventory service account + per-resource IAM -----
resource "google_service_account" "inventory" {
  project      = var.project_id
  account_id   = "inventory-${local.env}-sa"
  display_name = "Inventory Tool (${local.env})"
}

locals {
  inventory_member = "serviceAccount:${google_service_account.inventory.email}"
}

resource "google_project_iam_member" "inventory_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = local.inventory_member
}

resource "google_project_iam_member" "inventory_cloudsql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = local.inventory_member
  condition {
    title      = "only-${local.env}-cloudsql"
    expression = "resource.name.startsWith(\"projects/${var.project_id}/instances/stylist-${local.env}-pg\")"
  }
}

resource "google_project_iam_member" "inventory_cloudsql_instance_user" {
  project = var.project_id
  role    = "roles/cloudsql.instanceUser"
  member  = local.inventory_member
  condition {
    title      = "only-${local.env}-cloudsql"
    expression = "resource.name.startsWith(\"projects/${var.project_id}/instances/stylist-${local.env}-pg\")"
  }
}

resource "google_sql_user" "inventory_iam" {
  project  = var.project_id
  instance = module.cloud_sql.instance_name
  name     = trimsuffix(google_service_account.inventory.email, ".gserviceaccount.com")
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

resource "google_storage_bucket_iam_member" "inventory_clothing" {
  bucket = google_storage_bucket.clothing_photos.name
  role   = "roles/storage.objectAdmin"
  member = local.inventory_member
}

# Lets inventory mint signed URLs for the clothing bucket via iam.signBlob.
resource "google_service_account_iam_member" "inventory_sign_self" {
  service_account_id = google_service_account.inventory.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = local.inventory_member
}

# ----- Cloud Run services -----
module "weather" {
  source                = "../../modules/cloud-run-service"
  project_id            = var.project_id
  region                = var.region
  name                  = "stylist-${local.env}-weather"
  image                 = var.hello_image # Cloud Build replaces (lifecycle ignores)
  service_account_email = google_service_account.weather.email

  min_instances    = 0
  max_instances    = 5
  cpu              = "1"
  memory           = "512Mi"
  vpc_connector_id = data.terraform_remote_state.shared.outputs.vpc_connector_id

  env_vars = {
    APP_ENV              = local.env
    APP_NAME             = "stylist-weather"
    PROJECT_ID           = var.project_id
    REDIS_HOST           = module.memorystore.host
    REDIS_PORT           = tostring(module.memorystore.port)
    REDIS_AUTH_SECRET_ID = module.memorystore.auth_secret_id
  }

  ingress      = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  allow_public = false
  labels       = local.common_labels
}

module "inventory" {
  source                = "../../modules/cloud-run-service"
  project_id            = var.project_id
  region                = var.region
  name                  = "stylist-${local.env}-inventory"
  image                 = var.hello_image
  service_account_email = google_service_account.inventory.email

  min_instances    = 0
  max_instances    = 5
  cpu              = "1"
  memory           = "512Mi"
  vpc_connector_id = data.terraform_remote_state.shared.outputs.vpc_connector_id

  cloudsql_connection_name = module.cloud_sql.connection_name

  env_vars = {
    APP_ENV            = local.env
    APP_NAME           = "stylist-inventory"
    PROJECT_ID         = var.project_id
    REGION             = var.region
    DB_USER            = trimsuffix(google_service_account.inventory.email, ".gserviceaccount.com")
    DB_NAME            = "stylist"
    DB_HOST            = "/cloudsql"
    DB_CONNECTION_NAME = module.cloud_sql.connection_name
    CLOTHING_BUCKET    = google_storage_bucket.clothing_photos.name
    TRITON_BASE_URL    = var.triton_base_url
    QDRANT_BASE_URL    = var.qdrant_base_url
  }

  ingress      = "INGRESS_TRAFFIC_INTERNAL_ONLY"
  allow_public = false
  labels       = local.common_labels

  depends_on = [google_sql_user.inventory_iam]
}

module "agent" {
  source                = "../../modules/cloud-run-service"
  project_id            = var.project_id
  region                = var.region
  name                  = "stylist-${local.env}-agent"
  image                 = var.hello_image
  service_account_email = module.iam_dev.agent_orchestrator_sa_email

  min_instances    = 0
  max_instances    = 5
  cpu              = "2"
  memory           = "1Gi"
  timeout          = "300s"
  vpc_connector_id = data.terraform_remote_state.shared.outputs.vpc_connector_id

  # Inventory + weather are INGRESS_TRAFFIC_INTERNAL_ONLY and resolve to public
  # *.run.app IPs. With the default PRIVATE_RANGES_ONLY egress those calls would
  # bypass the connector, egress to the internet, and be rejected by the internal
  # ingress with an empty-body 404. ALL_TRAFFIC routes them through the connector
  # so they count as internal. Google APIs still work via Private Google Access.
  vpc_egress = "ALL_TRAFFIC"

  env_vars = {
    APP_ENV            = local.env
    APP_NAME           = "stylist-agent"
    PROJECT_ID         = var.project_id
    REGION             = var.region
    INVENTORY_BASE_URL = module.inventory.service_uri
    WEATHER_BASE_URL   = module.weather.service_uri
    FIRESTORE_DATABASE = module.firestore.database_name
    SESSIONS_BUCKET    = google_storage_bucket.agent_sessions.name
    LLM_MODE           = var.llm_base_url == "" ? "stub" : "openai"
    LLM_BASE_URL       = var.llm_base_url
    LLM_MODEL          = "mistralai/Mistral-7B-Instruct-v0.3"

    # Trusted frontend origin(s). Browser CORS preflights need this.
    CORS_ALLOW_ORIGINS = "https://app-${local.env}.${var.domain}"

    # Firebase Auth: token audience verification. One Firebase project per
    # GCP project, so reuse var.project_id.
    FIREBASE_PROJECT_ID = var.project_id
  }

  # Public; the only public service. Frontend (also public) calls /api/* + /chat here.
  ingress      = "INGRESS_TRAFFIC_ALL"
  allow_public = true

  dns_subdomain = "api-${local.env}" # api-dev.quantum-23.com
  domain        = var.domain
  dns_zone_name = data.terraform_remote_state.shared.outputs.dns_zone_name

  labels = local.common_labels
}

# Agent SA can invoke the private weather and inventory services.
resource "google_cloud_run_v2_service_iam_member" "agent_invokes_weather" {
  project  = var.project_id
  location = var.region
  name     = module.weather.service_name
  role     = "roles/run.invoker"
  member   = local.agent_orch_member
}

resource "google_cloud_run_v2_service_iam_member" "agent_invokes_inventory" {
  project  = var.project_id
  location = var.region
  name     = module.inventory.service_name
  role     = "roles/run.invoker"
  member   = local.agent_orch_member
}

# ----- Frontend (Next.js, public) -----
resource "google_service_account" "frontend" {
  account_id   = "stylist-${local.env}-frontend"
  display_name = "Stylist ${local.env} frontend runtime SA"
  project      = var.project_id
}

module "frontend" {
  source                = "../../modules/cloud-run-service"
  project_id            = var.project_id
  region                = var.region
  name                  = "stylist-${local.env}-frontend"
  image                 = var.hello_image # CI/CD swaps in services/frontend image
  service_account_email = google_service_account.frontend.email

  min_instances = 0
  max_instances = 5
  cpu           = "1"
  memory        = "512Mi"
  timeout       = "60s"

  env_vars = {
    APP_ENV  = local.env
    APP_NAME = "stylist-frontend"
    # NEXT_PUBLIC_AGENT_URL is baked at build-time; this runtime var is unused by
    # the standalone server but kept for diagnostics.
    NEXT_PUBLIC_AGENT_URL = "https://api-${local.env}.${var.domain}"
  }

  ingress      = "INGRESS_TRAFFIC_ALL"
  allow_public = true

  # Next.js standalone server only serves app routes; there's no /api/health
  # endpoint. Probe the root page instead (Cloud Run's GFE does NOT intercept
  # `/`, unlike `/healthz` / `/health` / `/ready`).
  health_path = "/"

  dns_subdomain = "app-${local.env}" # app-dev.quantum-23.com
  domain        = var.domain
  dns_zone_name = data.terraform_remote_state.shared.outputs.dns_zone_name

  labels = local.common_labels
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

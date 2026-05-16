/**
 * Reusable Cloud Run Job (v2) module.
 *
 * Phase 1.1 use case: db-migrate. Future phases reuse for one-shot tasks
 * (e.g. street-feed backfill, training-data export).
 */

resource "google_cloud_run_v2_job" "job" {
  project  = var.project_id
  name     = var.name
  location = var.region

  template {
    template {
      service_account = var.service_account_email
      timeout         = var.timeout
      max_retries     = var.max_retries

      vpc_access {
        connector = var.vpc_connector_id
        egress    = "PRIVATE_RANGES_ONLY"
      }

      containers {
        image = var.image

        resources {
          limits = {
            cpu    = var.cpu
            memory = var.memory
          }
        }

        dynamic "env" {
          for_each = var.env_vars
          content {
            name  = env.key
            value = env.value
          }
        }
      }
    }
  }

  labels = merge(var.labels, { service = var.name })

  lifecycle {
    ignore_changes = [
      client,
      client_version,
      template[0].template[0].containers[0].image,
    ]
  }
}

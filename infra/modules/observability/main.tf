/**
 * Observability module (Phase 0)
 *
 * Provides:
 *   • BigQuery dataset for ops analytics + log sink to it
 *   • Per-env budget alerts (label-filtered)
 *   • Notification channels (email)
 *   • Baseline alerting policies (Cloud Run 5xx, billing)
 *   • Langfuse hosted on Cloud Run + Cloud SQL (deferred from GKE to keep
 *     Phase 0 idle cost ~$30/mo; re-platform to GKE in Phase 1.2)
 */

# ----- Ops analytics BigQuery dataset -----
resource "google_bigquery_dataset" "ops_analytics" {
  project       = var.project_id
  dataset_id    = "ops_analytics"
  friendly_name = "Stylist Ops Analytics"
  description   = "Error logs and operational metrics from log sinks"
  location      = var.region

  labels = var.labels
}

# Log sink: errors -> BigQuery
resource "google_logging_project_sink" "errors_to_bq" {
  project = var.project_id
  name    = "stylist-errors-to-bq"

  destination = "bigquery.googleapis.com/projects/${var.project_id}/datasets/${google_bigquery_dataset.ops_analytics.dataset_id}"

  filter = <<-EOT
    severity>=ERROR
    AND (resource.labels.service_name=~"^stylist-" OR labels.app="stylist-agent")
  EOT

  unique_writer_identity = true

  bigquery_options {
    use_partitioned_tables = true
  }
}

resource "google_project_iam_member" "log_sink_bq_writer" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = google_logging_project_sink.errors_to_bq.writer_identity
}

# ----- Notification channel -----
resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "Stylist on-call email"
  type         = "email"

  labels = {
    email_address = var.alert_email
  }

  user_labels = var.labels
}

# ----- Per-env budget alerts -----
resource "google_billing_budget" "env_budget" {
  for_each = var.budgets

  billing_account = var.billing_account_id
  display_name    = "stylist-${each.key}-budget"

  budget_filter {
    projects = ["projects/${var.project_id}"]
    labels = {
      env = each.key
    }
  }

  amount {
    specified_amount {
      currency_code = "USD"
      units         = each.value
    }
  }

  dynamic "threshold_rules" {
    for_each = [0.5, 0.8, 1.0]
    content {
      threshold_percent = threshold_rules.value
      spend_basis       = "CURRENT_SPEND"
    }
  }

  all_updates_rule {
    monitoring_notification_channels = [
      google_monitoring_notification_channel.email.id
    ]
    disable_default_iam_recipients = false
  }
}

# ----- Baseline alerting policies -----
resource "google_monitoring_alert_policy" "cloud_run_5xx" {
  project      = var.project_id
  display_name = "Cloud Run 5xx > 1% (any stylist service)"
  combiner     = "OR"

  conditions {
    display_name = "5xx error rate"
    condition_threshold {
      filter = <<-EOT
        metric.type="run.googleapis.com/request_count"
        AND resource.type="cloud_run_revision"
        AND resource.labels.service_name=~"^stylist-"
        AND metric.labels.response_code_class="5xx"
      EOT
      duration   = "300s"
      comparison = "COMPARISON_GT"
      threshold_value = 0.01
      aggregations {
        alignment_period   = "60s"
        per_series_aligner = "ALIGN_RATE"
      }
    }
  }

  notification_channels = [google_monitoring_notification_channel.email.id]

  user_labels = var.labels
}

# ----- Langfuse on Cloud Run (Phase 0 minimal hosting) -----
# Deploys the official langfuse/langfuse image. Backend Postgres is the
# tiny shared Cloud SQL instance defined alongside this module's invocation.
# This deviates from the doc's GKE plan to keep Phase 0 idle cost minimal;
# re-platform to GKE in Phase 1.2 once GKE is online.
resource "google_cloud_run_v2_service" "langfuse" {
  count    = var.deploy_langfuse ? 1 : 0
  project  = var.project_id
  name     = "stylist-langfuse"
  location = var.region

  ingress = "INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER"

  template {
    service_account = var.langfuse_sa_email
    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    containers {
      image = "ghcr.io/langfuse/langfuse:latest"

      resources {
        limits = {
          cpu    = "1"
          memory = "1Gi"
        }
      }

      env {
        name  = "DATABASE_URL"
        value_source {
          secret_key_ref {
            secret  = "langfuse-database-url"
            version = "latest"
          }
        }
      }
      env {
        name = "NEXTAUTH_SECRET"
        value_source {
          secret_key_ref {
            secret  = "langfuse-nextauth-secret"
            version = "latest"
          }
        }
      }
      env {
        name = "SALT"
        value_source {
          secret_key_ref {
            secret  = "langfuse-salt"
            version = "latest"
          }
        }
      }
      env {
        name  = "NEXTAUTH_URL"
        value = "https://langfuse.internal.${var.domain}"
      }

      ports {
        container_port = 3000
      }
    }
  }

  labels = merge(var.labels, { component = "langfuse" })
}

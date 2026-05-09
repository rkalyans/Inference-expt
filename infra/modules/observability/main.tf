/**
 * Observability module (Phase 0)
 *
 * Provides:
 *   • BigQuery dataset for ops analytics + log sink to it
 *   • Per-env budget alerts (label-filtered)
 *   • Notification channels (email)
 *   • Baseline alerting policies (Cloud Run 5xx, billing)
 *
 * Langfuse runs as SaaS (cloud.langfuse.com). Client credentials live in
 * Secret Manager (`langfuse-public-key`, `langfuse-secret-key`, `langfuse-host`)
 * and are mounted into the agent service in later phases.
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
    email_address = var.owner_email
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
      filter = join(" AND ", [
        "metric.type=\"run.googleapis.com/request_count\"",
        "resource.type=\"cloud_run_revision\"",
        "resource.label.service_name=monitoring.regex.full_match(\"stylist-.*\")",
        "metric.label.response_code_class=\"5xx\"",
      ])
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


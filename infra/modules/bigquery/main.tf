/**
 * BigQuery — analytics + training_data datasets.
 *
 * `ops_analytics` already exists in the observability module.
 * `analytics`     — product/usage events, recommendation outcomes
 * `training_data` — joined views feeding LoRA pipeline (Phase 2.3)
 */

resource "google_bigquery_dataset" "analytics" {
  project       = var.project_id
  dataset_id    = "stylist_${var.env}_analytics"
  friendly_name = "Stylist ${var.env} analytics"
  description   = "Product/usage events, recommendation outcomes, feedback"
  location      = var.location

  default_table_expiration_ms = var.env == "prod" ? null : 1000 * 60 * 60 * 24 * 90 # 90 days

  labels = var.labels
}

resource "google_bigquery_dataset" "training_data" {
  project       = var.project_id
  dataset_id    = "stylist_${var.env}_training_data"
  friendly_name = "Stylist ${var.env} training data"
  description   = "Joined recommendation/feedback views feeding the LoRA pipeline"
  location      = var.location

  labels = var.labels
}

output "analytics_dataset_id" {
  value = google_bigquery_dataset.analytics.dataset_id
}

output "training_dataset_id" {
  value = google_bigquery_dataset.training_data.dataset_id
}

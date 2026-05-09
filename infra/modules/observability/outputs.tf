output "ops_dataset_id" {
  value = google_bigquery_dataset.ops_analytics.dataset_id
}

output "notification_channel_id" {
  value = google_monitoring_notification_channel.email.id
}

output "ops_dataset_id" {
  value = google_bigquery_dataset.ops_analytics.dataset_id
}

output "notification_channel_id" {
  value = google_monitoring_notification_channel.email.id
}

output "langfuse_url" {
  value = try(google_cloud_run_v2_service.langfuse[0].uri, null)
}

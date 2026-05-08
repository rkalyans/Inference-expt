output "service_name" {
  value = google_cloud_run_v2_service.service.name
}

output "service_uri" {
  value = google_cloud_run_v2_service.service.uri
}

output "domain_mapping_status" {
  value = try(google_cloud_run_domain_mapping.domain[0].status, null)
}

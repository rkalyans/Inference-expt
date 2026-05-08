output "zone_name" {
  value = google_dns_managed_zone.primary.name
}

output "zone_dns_name" {
  value = google_dns_managed_zone.primary.dns_name
}

output "name_servers" {
  description = "Configure these at the domain registrar (Cloud Domains)"
  value       = google_dns_managed_zone.primary.name_servers
}

output "internal_zone_name" {
  value = google_dns_managed_zone.internal.name
}

output "internal_zone_dns_name" {
  value = google_dns_managed_zone.internal.dns_name
}

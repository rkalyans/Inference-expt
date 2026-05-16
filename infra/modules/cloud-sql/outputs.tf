output "instance_name" {
  value = google_sql_database_instance.primary.name
}

output "connection_name" {
  description = "Use with Cloud SQL Auth Proxy: <project>:<region>:<instance>"
  value       = google_sql_database_instance.primary.connection_name
}

output "private_ip" {
  value = google_sql_database_instance.primary.private_ip_address
}

output "database_name" {
  value = google_sql_database.stylist.name
}

output "root_password_secret_id" {
  value = google_secret_manager_secret.root_password.secret_id
}

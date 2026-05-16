output "database_name" {
  value = google_firestore_database.db.name
}

output "database_id" {
  description = "Full database resource id, e.g. projects/<p>/databases/stylist-dev"
  value       = "projects/${var.project_id}/databases/${google_firestore_database.db.name}"
}

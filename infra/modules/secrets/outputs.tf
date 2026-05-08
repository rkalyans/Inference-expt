output "secret_ids" {
  value = { for k, s in google_secret_manager_secret.secret : k => s.id }
}

output "host" {
  value = google_redis_instance.cache.host
}

output "port" {
  value = google_redis_instance.cache.port
}

output "auth_secret_id" {
  value = google_secret_manager_secret.redis_auth.secret_id
}

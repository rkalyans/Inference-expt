/**
 * Memorystore Redis — private VPC, AUTH enabled, env-sized.
 *
 * Phase 1 use cases:
 *   - Weather Tool API: 15 min TTL on current weather, 1 hr on forecasts
 *   - Inventory Tool API: cache CLIP embeddings for recently uploaded items
 *   - Agent Orchestrator: rate-limit + idempotency keys
 */

resource "google_redis_instance" "cache" {
  project        = var.project_id
  region         = var.region
  name           = "stylist-${var.env}-redis"
  display_name   = "Stylist ${var.env} cache"
  tier           = var.high_availability ? "STANDARD_HA" : "BASIC"
  memory_size_gb = var.memory_size_gb
  redis_version  = "REDIS_7_0"

  authorized_network = var.vpc_id
  connect_mode       = "PRIVATE_SERVICE_ACCESS"

  auth_enabled            = true
  transit_encryption_mode = "SERVER_AUTHENTICATION"

  redis_configs = {
    maxmemory-policy = "allkeys-lru"
  }

  labels = var.labels
}

# Stash the AUTH string in Secret Manager so apps can read it like any other secret.
resource "google_secret_manager_secret" "redis_auth" {
  project   = var.project_id
  secret_id = "stylist-${var.env}-redis-auth"
  replication { auto {} }
  labels = var.labels
}

resource "google_secret_manager_secret_version" "redis_auth" {
  secret      = google_secret_manager_secret.redis_auth.id
  secret_data = google_redis_instance.cache.auth_string
}

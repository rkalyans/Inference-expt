/**
 * Firestore — one named database per env (Native mode).
 *
 * Notes:
 *   - GCP allows multiple Firestore databases per project (since 2024).
 *   - Database name is bound by Firestore naming rules: lowercase + hyphens.
 *   - Multi-region locations: nam5 (us), eur3 (eu). Single-region for cost.
 */

resource "google_firestore_database" "db" {
  project                           = var.project_id
  name                              = "stylist-${var.env}"
  location_id                       = var.location
  type                              = "FIRESTORE_NATIVE"
  concurrency_mode                  = "OPTIMISTIC"
  app_engine_integration_mode       = "DISABLED"
  point_in_time_recovery_enablement = "POINT_IN_TIME_RECOVERY_ENABLED"
  delete_protection_state           = var.env == "prod" ? "DELETE_PROTECTION_ENABLED" : "DELETE_PROTECTION_DISABLED"
  deletion_policy                   = var.env == "prod" ? "ABANDON" : "DELETE"
}

# Composite indexes for common query patterns.
# (Single-field indexes are auto-created; only compound indexes need declaring.)

resource "google_firestore_index" "user_recommendations" {
  project    = var.project_id
  database   = google_firestore_database.db.name
  collection = "recommendations"

  fields {
    field_path = "user_id"
    order      = "ASCENDING"
  }
  fields {
    field_path = "created_at"
    order      = "DESCENDING"
  }
}

resource "google_firestore_index" "user_sessions" {
  project    = var.project_id
  database   = google_firestore_database.db.name
  collection = "agent_sessions"

  fields {
    field_path = "user_id"
    order      = "ASCENDING"
  }
  fields {
    field_path = "status"
    order      = "ASCENDING"
  }
  fields {
    field_path = "created_at"
    order      = "DESCENDING"
  }
}

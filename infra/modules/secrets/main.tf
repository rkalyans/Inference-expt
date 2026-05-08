/**
 * Secrets module — creates Secret Manager entries (no values).
 * Values are populated by `scripts/05-seed-secrets.sh` from local env vars.
 */

resource "google_secret_manager_secret" "secret" {
  for_each = toset(var.secret_names)

  project   = var.project_id
  secret_id = each.value

  replication {
    auto {}
  }

  labels = merge(var.labels, {
    secret_name = each.value
  })
}

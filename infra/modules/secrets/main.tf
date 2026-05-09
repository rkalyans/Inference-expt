/**
 * Secrets module — creates Secret Manager entries (no values).
 * Values are added manually — see PHASE-0-RUNBOOK.md §6 (`gcloud secrets
 * versions add ...`).
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

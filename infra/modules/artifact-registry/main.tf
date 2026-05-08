/**
 * Artifact Registry — single Docker repo shared across envs.
 * Image tags carry env (e.g. stylist-hello:dev-abc123).
 */

resource "google_artifact_registry_repository" "docker" {
  project       = var.project_id
  location      = var.region
  repository_id = "stylist-docker"
  description   = "Container images for stylist-agent (all envs)"
  format        = "DOCKER"

  cleanup_policies {
    id     = "keep-recent-tagged"
    action = "KEEP"
    most_recent_versions {
      keep_count = 20
    }
  }

  cleanup_policies {
    id     = "delete-untagged-after-7d"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "604800s"
    }
  }

  labels = var.labels
}

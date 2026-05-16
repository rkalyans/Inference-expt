/**
 * Reusable Cloud Run v2 service module with mandatory labels,
 * env-scoped service account, and DNS A record on quantum-23.com subdomain.
 */

resource "google_cloud_run_v2_service" "service" {
  project  = var.project_id
  name     = var.name
  location = var.region

  ingress = var.ingress

  template {
    service_account = var.service_account_email
    timeout         = var.timeout

    scaling {
      min_instance_count = var.min_instances
      max_instance_count = var.max_instances
    }

    dynamic "vpc_access" {
      for_each = var.vpc_connector_id == "" ? [] : [1]
      content {
        connector = var.vpc_connector_id
        egress    = var.vpc_egress
      }
    }

    dynamic "volumes" {
      for_each = var.cloudsql_connection_name == "" ? [] : [1]
      content {
        name = "cloudsql"
        cloud_sql_instance {
          instances = [var.cloudsql_connection_name]
        }
      }
    }

    containers {
      image = var.image

      resources {
        limits = {
          cpu    = var.cpu
          memory = var.memory
        }
      }

      dynamic "env" {
        for_each = var.env_vars
        content {
          name  = env.key
          value = env.value
        }
      }

      dynamic "env" {
        for_each = var.secret_env_vars
        content {
          name = env.key
          value_source {
            secret_key_ref {
              secret  = env.value
              version = "latest"
            }
          }
        }
      }

      dynamic "volume_mounts" {
        for_each = var.cloudsql_connection_name == "" ? [] : [1]
        content {
          name       = "cloudsql"
          mount_path = "/cloudsql"
        }
      }

      ports {
        container_port = var.container_port
      }

      startup_probe {
        http_get {
          path = var.health_path
        }
        initial_delay_seconds = 5
        period_seconds        = 10
        failure_threshold     = 6
      }

      liveness_probe {
        http_get {
          path = var.health_path
        }
        period_seconds    = 30
        failure_threshold = 3
      }
    }
  }

  labels = merge(var.labels, { service = var.name })

  lifecycle {
    ignore_changes = [
      client,
      client_version,
      # Cloud Build deploys the real image as a new revision after Terraform
      # creates the service. Don't revert that on subsequent `terraform apply`.
      template[0].containers[0].image,
    ]
  }
}

# Allow public invocation if requested
resource "google_cloud_run_v2_service_iam_member" "public" {
  count    = var.allow_public ? 1 : 0
  project  = var.project_id
  location = google_cloud_run_v2_service.service.location
  name     = google_cloud_run_v2_service.service.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# DNS A record (CNAME to ghs.googlehosted.com) for the subdomain
resource "google_cloud_run_domain_mapping" "domain" {
  count    = var.dns_subdomain != "" ? 1 : 0
  project  = var.project_id
  location = var.region
  name     = "${var.dns_subdomain}.${var.domain}"

  metadata {
    namespace = var.project_id
    labels    = var.labels
  }

  spec {
    route_name = google_cloud_run_v2_service.service.name
  }
}

# CNAME record inside the Cloud DNS zone so the subdomain actually resolves.
# Cloud Run v1 subdomain mappings are always served via ghs.googlehosted.com;
# this is the documented stable target and is why we don't read
# google_cloud_run_domain_mapping.status.resource_records (empty on first plan).
resource "google_dns_record_set" "subdomain_cname" {
  count        = var.dns_subdomain != "" && var.dns_zone_name != "" ? 1 : 0
  project      = var.project_id
  managed_zone = var.dns_zone_name
  name         = "${var.dns_subdomain}.${var.domain}."
  type         = "CNAME"
  ttl          = 300
  rrdatas      = ["ghs.googlehosted.com."]

  depends_on = [google_cloud_run_domain_mapping.domain]
}

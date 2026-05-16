/**
 * GKE inference cluster.
 *
 * - Regional VPC-native private cluster (nodes have no public IPs).
 * - Workload Identity enabled cluster-wide.
 * - Two node pools:
 *     cpu  : e2-standard-4, autoscaling 1..3, runs Qdrant + system pods
 *     gpu  : g2-standard-8 + 1x NVIDIA L4, autoscaling 0..N, taint nvidia.com/gpu=present
 *            Hosts vLLM (Mistral-7B-Instruct) and Triton (FashionCLIP).
 * - Release channel REGULAR for managed upgrades.
 *
 * Caller wires this into one env at a time and consumes `cluster_name` /
 * `cluster_endpoint` / `cluster_ca_cert` to configure kubectl + helm.
 */

resource "google_service_account" "node" {
  project      = var.project_id
  account_id   = "gke-${var.env}-node-sa"
  display_name = "GKE inference node SA (${var.env})"
}

# Minimum scopes for nodes: log/metric writers + Artifact Registry reader.
resource "google_project_iam_member" "node_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_artifact_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_container_cluster" "this" {
  project  = var.project_id
  name     = "stylist-${var.env}-gke"
  location = var.region

  network    = var.vpc_self_link
  subnetwork = var.subnet_self_link

  release_channel { channel = "REGULAR" }

  # VPC-native (Alias IPs) is required for Workload Identity + private clusters.
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pods_range_name
    services_secondary_range_name = var.services_range_name
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false # public master endpoint for kubectl from Cloud Shell
    master_ipv4_cidr_block  = var.master_cidr
  }

  master_authorized_networks_config {
    dynamic "cidr_blocks" {
      for_each = var.master_authorized_cidrs
      content {
        cidr_block   = cidr_blocks.value.cidr
        display_name = cidr_blocks.value.name
      }
    }
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # We define our own node pools below; remove the default.
  remove_default_node_pool = true
  initial_node_count       = 1

  deletion_protection = var.deletion_protection

  resource_labels = merge(var.labels, { service = "gke-inference" })

  # Disable basic auth + legacy ABAC for security.
  enable_legacy_abac = false

  # Required for ILBs & NEG-based services.
  networking_mode = "VPC_NATIVE"
}

# ----- CPU node pool -----
resource "google_container_node_pool" "cpu" {
  project    = var.project_id
  name       = "cpu-pool"
  location   = var.region
  cluster    = google_container_cluster.this.name

  autoscaling {
    min_node_count = var.cpu_min_nodes
    max_node_count = var.cpu_max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.cpu_machine_type
    disk_size_gb = 50
    disk_type    = "pd-balanced"

    service_account = google_service_account.node.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config { mode = "GKE_METADATA" }

    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    tags   = ["stylist-gke-node"]
    labels = merge(var.labels, { pool = "cpu" })
  }
}

# ----- GPU node pool (L4) -----
resource "google_container_node_pool" "gpu" {
  project  = var.project_id
  name     = "gpu-l4-pool"
  location = var.region
  cluster  = google_container_cluster.this.name

  autoscaling {
    min_node_count = var.gpu_min_nodes
    max_node_count = var.gpu_max_nodes
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  node_config {
    machine_type = var.gpu_machine_type # default g2-standard-8 (1x L4)
    disk_size_gb = var.gpu_disk_size_gb  # weights are big; default 200
    disk_type    = "pd-balanced"

    service_account = google_service_account.node.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    workload_metadata_config { mode = "GKE_METADATA" }

    guest_accelerator {
      type  = var.gpu_accelerator_type # nvidia-l4
      count = var.gpu_accelerator_count

      gpu_driver_installation_config {
        gpu_driver_version = "LATEST"
      }
    }

    # Reserve the GPU pool for inference workloads only.
    taint {
      key    = "nvidia.com/gpu"
      value  = "present"
      effect = "NO_SCHEDULE"
    }

    shielded_instance_config {
      enable_secure_boot          = false # GPU drivers require kernel modules
      enable_integrity_monitoring = true
    }

    tags   = ["stylist-gke-node", "stylist-gke-gpu"]
    labels = merge(var.labels, { pool = "gpu", "nvidia.com/gpu" = "present" })
  }

  # GPU pools occasionally fail to scale due to regional capacity. Don't
  # block the rest of the apply on it.
  timeouts {
    create = "30m"
    update = "30m"
    delete = "20m"
  }
}

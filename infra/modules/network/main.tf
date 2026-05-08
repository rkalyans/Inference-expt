/**
 * Network module — single VPC with one subnet per environment.
 *
 * Subnets:
 *   dev     10.10.0.0/20
 *   staging 10.20.0.0/20
 *   prod    10.30.0.0/20
 *
 * Plus secondary ranges for GKE pods/services in Phase 1.2.
 */

resource "google_compute_network" "vpc" {
  name                    = "stylist-vpc"
  project                 = var.project_id
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "Shared VPC for all stylist-agent environments"
}

resource "google_compute_subnetwork" "subnet" {
  for_each = var.subnets

  name          = "stylist-${each.key}-subnet"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.id
  ip_cidr_range = each.value.primary_cidr

  private_ip_google_access = true

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = each.value.pods_cidr
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = each.value.services_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_10_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# Cloud Router + NAT (one per region, shared by all envs — egress isolation
# is enforced via service-account-level firewall rules, not separate NATs)
resource "google_compute_router" "router" {
  name    = "stylist-router"
  project = var.project_id
  region  = var.region
  network = google_compute_network.vpc.id
}

resource "google_compute_router_nat" "nat" {
  name                               = "stylist-nat"
  project                            = var.project_id
  region                             = var.region
  router                             = google_compute_router.router.name
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# Default firewall — deny everything; explicit allow rules per env in later phases
resource "google_compute_firewall" "deny_all_ingress" {
  name      = "stylist-deny-all-ingress"
  project   = var.project_id
  network   = google_compute_network.vpc.id
  priority  = 65534
  direction = "INGRESS"

  deny {
    protocol = "all"
  }
  source_ranges = ["0.0.0.0/0"]
}

# Allow IAP tunnel SSH for emergency access (audit logged)
resource "google_compute_firewall" "allow_iap_ssh" {
  name      = "stylist-allow-iap-ssh"
  project   = var.project_id
  network   = google_compute_network.vpc.id
  priority  = 1000
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }
  source_ranges = ["35.235.240.0/20"] # Google IAP range
  target_tags   = ["allow-iap-ssh"]
}

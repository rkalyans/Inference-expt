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

# ----- Private Services Access (PSA) -----
# Reserved IP range that Google-managed services (Cloud SQL, Memorystore, etc.)
# allocate from when given a private IP. Single PSA range shared by all envs.
resource "google_compute_global_address" "psa_range" {
  name          = "stylist-psa-range"
  project       = var.project_id
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc.id
  description   = "Reserved range for private services (Cloud SQL, Memorystore)"
}

resource "google_service_networking_connection" "psa" {
  network                 = google_compute_network.vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.psa_range.name]
}

# Allow Cloud Run / GKE to reach private services via the PSA range
resource "google_compute_firewall" "allow_internal_to_psa" {
  name      = "stylist-allow-internal-to-psa"
  project   = var.project_id
  network   = google_compute_network.vpc.id
  priority  = 1000
  direction = "EGRESS"

  allow { protocol = "tcp" }
  destination_ranges = ["10.0.0.0/8"] # covers PSA + subnets
}

# ----- GKE-bound firewall rules (Phase 1.2) -----
# Cloud Run (via the serverless VPC connector) -> GKE pods on inference ports.
# Targets the per-env pod CIDR; covers vLLM (8000), Triton (8001/8002), Qdrant (6333).
resource "google_compute_firewall" "allow_connector_to_gke" {
  name      = "stylist-allow-connector-to-gke"
  project   = var.project_id
  network   = google_compute_network.vpc.id
  priority  = 1000
  direction = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["8000", "8001", "8002", "6333", "6334"]
  }

  source_ranges = [var.vpc_connector_cidr]
  target_tags   = ["stylist-gke-node"]
}

# Allow GKE health checks (Google's load balancer probers) to reach node ports.
resource "google_compute_firewall" "allow_gke_health_checks" {
  name      = "stylist-allow-gke-health-checks"
  project   = var.project_id
  network   = google_compute_network.vpc.id
  priority  = 1000
  direction = "INGRESS"

  allow {
    protocol = "tcp"
  }

  # Google health-check + ILB prober ranges
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22", "209.85.152.0/22", "209.85.204.0/22"]
  target_tags   = ["stylist-gke-node"]
}

# Allow node-to-node + node-to-pod traffic (kubelet, kube-proxy, CNI).
resource "google_compute_firewall" "allow_gke_intra" {
  name      = "stylist-allow-gke-intra"
  project   = var.project_id
  network   = google_compute_network.vpc.id
  priority  = 1000
  direction = "INGRESS"

  allow { protocol = "tcp" }
  allow { protocol = "udp" }
  allow { protocol = "icmp" }

  source_tags = ["stylist-gke-node"]
  target_tags = ["stylist-gke-node"]
}

# ----- Serverless VPC Access Connector -----
# Lets Cloud Run services / Cloud Run Jobs reach private resources (Cloud SQL,
# Memorystore, internal-LB-fronted GKE Services).
resource "google_vpc_access_connector" "serverless" {
  name          = "stylist-vpc-conn"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.vpc.name
  ip_cidr_range = var.vpc_connector_cidr
  min_instances = 2
  max_instances = 3
  machine_type  = "e2-micro"
}

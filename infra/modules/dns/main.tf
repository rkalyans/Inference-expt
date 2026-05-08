/**
 * DNS module — managed zone for quantum-23.com.
 *
 * After applying, take the `name_servers` output and configure them at the
 * domain registrar (Cloud Domains). Phase 0 succeeds when NS records propagate.
 */

resource "google_dns_managed_zone" "primary" {
  name        = "quantum-23-com"
  project     = var.project_id
  dns_name    = "${var.domain}."
  description = "Public zone for ${var.domain} (all envs share this zone)"
  visibility  = "public"

  dnssec_config {
    state = "on"
  }

  labels = var.labels
}

# Reserve subdomains as placeholder TXT records so DNS resolves immediately,
# even before Cloud Run services are created. Real A/AAAA records are added
# later by the cloud-run-service module.
resource "google_dns_record_set" "placeholder_root" {
  project      = var.project_id
  managed_zone = google_dns_managed_zone.primary.name
  name         = "${var.domain}."
  type         = "TXT"
  ttl          = 300
  rrdatas      = ["\"stylist-agent placeholder — Phase 0 bootstrap\""]
}

# Internal private zone for service-to-service discovery (e.g. langfuse.internal.quantum-23.com)
resource "google_dns_managed_zone" "internal" {
  name        = "quantum-23-internal"
  project     = var.project_id
  dns_name    = "internal.${var.domain}."
  description = "Private zone for internal service discovery"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = var.vpc_self_link
    }
  }

  labels = var.labels
}

output "vpc_id" {
  value = google_compute_network.vpc.id
}

output "vpc_name" {
  value = google_compute_network.vpc.name
}

output "vpc_self_link" {
  value = google_compute_network.vpc.self_link
}

output "subnets" {
  value = {
    for k, s in google_compute_subnetwork.subnet : k => {
      id            = s.id
      self_link     = s.self_link
      cidr          = s.ip_cidr_range
      region        = s.region
      pods_range    = "pods"
      services_range = "services"
      master_cidr   = var.subnets[k].master_cidr
    }
  }
}

output "psa_connection" {
  description = "Private Services Access connection (depend on this from data modules)"
  value       = google_service_networking_connection.psa.network
}

output "vpc_connector_id" {
  description = "Serverless VPC Access connector — pass to Cloud Run vpc_access.connector"
  value       = google_vpc_access_connector.serverless.id
}

output "vpc_connector_name" {
  value = google_vpc_access_connector.serverless.name
}

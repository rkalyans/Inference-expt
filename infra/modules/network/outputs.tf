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
      id        = s.id
      self_link = s.self_link
      cidr      = s.ip_cidr_range
      region    = s.region
    }
  }
}

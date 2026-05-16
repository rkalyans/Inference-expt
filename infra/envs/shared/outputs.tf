output "vpc_self_link" {
  value = module.network.vpc_self_link
}

output "psa_connection" {
  description = "PSA connection — env stacks depend on this before creating Cloud SQL/Memorystore"
  value       = module.network.psa_connection
}

output "vpc_connector_id" {
  description = "Serverless VPC Access connector — pass to Cloud Run for private connectivity"
  value       = module.network.vpc_connector_id
}

output "subnets" {
  value = module.network.subnets
}

output "dns_zone_name" {
  value = module.dns.zone_name
}

output "dns_name_servers" {
  description = "Configure these at the registrar for quantum-23.com"
  value       = module.dns.name_servers
}

output "artifact_registry_url" {
  value = module.artifact_registry.repository_url
}

output "cloudbuild_sa" {
  value = module.iam_shared.cloudbuild_sa_email
}

output "terraform_sa" {
  value = module.iam_shared.terraform_sa_email
}

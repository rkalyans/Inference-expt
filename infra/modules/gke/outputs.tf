output "cluster_name" { value = google_container_cluster.this.name }
output "cluster_id"   { value = google_container_cluster.this.id }
output "cluster_endpoint" {
  value     = google_container_cluster.this.endpoint
  sensitive = true
}
output "cluster_ca_cert" {
  value     = google_container_cluster.this.master_auth[0].cluster_ca_certificate
  sensitive = true
}
output "cluster_location" { value = google_container_cluster.this.location }

output "node_sa_email" { value = google_service_account.node.email }
output "node_sa_name"  { value = google_service_account.node.name }

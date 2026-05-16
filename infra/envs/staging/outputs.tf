output "hello_service_uri" {
  value = module.hello_world.service_uri
}

output "weather_service_uri"   { value = module.weather.service_uri }
output "inventory_service_uri" { value = module.inventory.service_uri }
output "agent_service_uri" {
  value = module.agent.service_uri
}

output "frontend_service_uri" {
  value = module.frontend.service_uri
}

output "service_accounts" {
  value = {
    agent_orchestrator = module.iam_staging.agent_orchestrator_sa_email
    weather            = google_service_account.weather.email
    inventory          = google_service_account.inventory.email
    db_migrate         = google_service_account.db_migrate.email
    frontend           = google_service_account.frontend.email
    gke_node           = module.gke.node_sa_email
  }
}

output "gke" {
  value = {
    cluster_name = module.gke.cluster_name
    location     = module.gke.cluster_location
  }
}

output "agent_orch_sa" {
  value = module.iam_staging.agent_orchestrator_sa_email
}

output "buckets" {
  value = {
    clothing_photos    = google_storage_bucket.clothing_photos.name
    agent_sessions     = google_storage_bucket.agent_sessions.name
    model_weights      = google_storage_bucket.model_weights.name
    street_feed_frames = google_storage_bucket.street_feed_frames.name
  }
}

output "cloud_sql" {
  value = {
    instance        = module.cloud_sql.instance_name
    connection_name = module.cloud_sql.connection_name
    private_ip      = module.cloud_sql.private_ip
    database        = module.cloud_sql.database_name
    root_secret_id  = module.cloud_sql.root_password_secret_id
  }
  sensitive = true
}

output "firestore_database" {
  value = module.firestore.database_name
}

output "redis" {
  value = {
    host           = module.memorystore.host
    port           = module.memorystore.port
    auth_secret_id = module.memorystore.auth_secret_id
  }
  sensitive = true
}

output "bigquery_datasets" {
  value = {
    analytics     = module.bigquery.analytics_dataset_id
    training_data = module.bigquery.training_dataset_id
  }
}

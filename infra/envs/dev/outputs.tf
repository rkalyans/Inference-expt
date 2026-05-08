output "hello_service_uri" {
  value = module.hello_world.service_uri
}

output "agent_orch_sa" {
  value = module.iam_dev.agent_orchestrator_sa_email
}

output "buckets" {
  value = {
    clothing_photos = google_storage_bucket.clothing_photos.name
    agent_sessions  = google_storage_bucket.agent_sessions.name
  }
}

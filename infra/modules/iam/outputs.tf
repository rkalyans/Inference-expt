output "cloudbuild_sa_email" {
  value = try(google_service_account.cloudbuild[0].email, null)
}

output "terraform_sa_email" {
  value = try(google_service_account.terraform[0].email, null)
}

output "agent_orchestrator_sa_email" {
  value = try(google_service_account.agent_orchestrator[0].email, null)
}

output "inference_sa_email" {
  value = try(google_service_account.inference[0].email, null)
}

output "street_feed_sa_email" {
  value = try(google_service_account.street_feed[0].email, null)
}

output "env_tag_key_id" {
  value = try(google_tags_tag_key.env[0].id, null)
}

output "env_tag_value_ids" {
  value = { for k, v in google_tags_tag_value.env_values : k => v.id }
}

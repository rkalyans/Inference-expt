output "hello_service_uri" {
  value = module.hello_world.service_uri
}

output "agent_orch_sa" {
  value = module.iam_staging.agent_orchestrator_sa_email
}

variable "project_id" {
  type    = string
  default = "inference-expt"
}

variable "region" {
  type    = string
  default = "us-east4"
}

variable "domain" {
  type    = string
  default = "quantum-23.com"
}

variable "hello_image" {
  type        = string
  description = <<-EOT
    Container image for the hello-world Cloud Run service.
    Default is Google's public hello image so Terraform can create the service
    before Cloud Build builds the real one. After Cloud Build deploys a real
    revision, the service module ignores image changes (see
    modules/cloud-run-service/main.tf lifecycle block).
  EOT
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "migrate_image" {
  type        = string
  description = "db-migrate Cloud Run Job image (Cloud Build replaces it)"
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

# ----- Phase 1.2 inference URLs -----
# Populated AFTER `kubectl apply -f infra/k8s/inference/` allocates ILB IPs.
# See PHASE-1-RUNBOOK §1.2 step "Wire URLs back into terraform".
variable "llm_base_url" {
  type        = string
  default     = ""
  description = "vLLM ILB URL e.g. http://10.10.0.5/v1. When empty, agent runs in LLM_MODE=stub."
}

variable "triton_base_url" {
  type    = string
  default = ""
}

variable "qdrant_base_url" {
  type    = string
  default = ""
}

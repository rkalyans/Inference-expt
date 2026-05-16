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
  description = "Placeholder image; Cloud Build deploys the real one as a new revision."
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

variable "llm_base_url" {
  type    = string
  default = ""
}
variable "triton_base_url" {
  type    = string
  default = ""
}
variable "qdrant_base_url" {
  type    = string
  default = ""
}

variable "migrate_image" {
  type        = string
  description = "db-migrate Cloud Run Job image (Cloud Build replaces it)"
  default     = "us-docker.pkg.dev/cloudrun/container/hello"
}

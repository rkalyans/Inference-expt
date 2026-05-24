variable "project_id" { type = string }
variable "region"     { type = string }
variable "name"       { type = string }
variable "image"      { type = string }

variable "service_account_email" { type = string }

variable "min_instances" {
  type    = number
  default = 0
}
variable "max_instances" {
  type    = number
  default = 5
}

variable "cpu" {
  type    = string
  default = "1"
}
variable "memory" {
  type    = string
  default = "512Mi"
}
variable "container_port" {
  type    = number
  default = 8080
}
variable "health_path" {
  type = string
  # NOTE: do NOT use `/healthz` — Cloud Run's edge frontend intercepts
  # `/healthz`, `/health`, `/ready` and returns its own 404 page before
  # the request reaches the container. Use a non-reserved path instead.
  default = "/api/health"
}

variable "ingress" {
  type    = string
  default = "INGRESS_TRAFFIC_ALL"
}

variable "allow_public" {
  type    = bool
  default = false
}

variable "env_vars" {
  type    = map(string)
  default = {}
}

variable "secret_env_vars" {
  type        = map(string)
  description = "Map of ENV_NAME -> Secret Manager secret_id"
  default     = {}
}

variable "dns_subdomain" {
  type        = string
  default     = ""
  description = "If set, creates domain mapping <subdomain>.<domain>"
}

variable "domain" {
  type    = string
  default = "quantum-23.com"
}

variable "dns_zone_name" {
  type        = string
  default     = ""
  description = "Cloud DNS managed-zone name (e.g. quantum-23-com). If set along with dns_subdomain, a CNAME <subdomain>.<domain> -> ghs.googlehosted.com is created so the domain mapping resolves publicly."
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "vpc_connector_id" {
  type        = string
  default     = ""
  description = "Optional Serverless VPC Access connector for private connectivity"
}

variable "vpc_egress" {
  type    = string
  default = "PRIVATE_RANGES_ONLY"
}

variable "cloudsql_connection_name" {
  type        = string
  default     = ""
  description = "Optional Cloud SQL connection name to mount via /cloudsql/<conn>"
}

variable "timeout" {
  type    = string
  default = "60s"
}

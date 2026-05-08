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
  type    = string
  default = "/healthz"
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

variable "labels" {
  type    = map(string)
  default = {}
}

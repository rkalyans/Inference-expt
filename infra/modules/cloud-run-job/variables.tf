variable "project_id"            { type = string }
variable "region"                { type = string }
variable "name"                  { type = string }
variable "image"                 { type = string }
variable "service_account_email" { type = string }
variable "vpc_connector_id"      { type = string }

variable "cpu" {
  type    = string
  default = "1"
}
variable "memory" {
  type    = string
  default = "512Mi"
}
variable "timeout" {
  type    = string
  default = "900s"
}
variable "max_retries" {
  type    = number
  default = 1
}

variable "env_vars" {
  type    = map(string)
  default = {}
}

variable "labels" {
  type    = map(string)
  default = {}
}

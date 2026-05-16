variable "project_id"    { type = string }
variable "region"        { type = string }
variable "env"           { type = string }
variable "vpc_self_link" { type = string }

variable "tier" {
  type        = string
  description = "Machine tier (e.g. db-f1-micro, db-custom-2-7680)"
  default     = "db-f1-micro"
}

variable "disk_size_gb" {
  type    = number
  default = 20
}

variable "high_availability" {
  type    = bool
  default = false
}

variable "iam_user_email" {
  type        = string
  description = "Service account email to grant IAM DB auth (leave empty to skip)"
  default     = ""
}

variable "labels" {
  type    = map(string)
  default = {}
}

variable "project_id" { type = string }
variable "region"     { type = string }
variable "env"        { type = string }
variable "vpc_id"     { type = string }

variable "memory_size_gb" {
  type    = number
  default = 1
}

variable "high_availability" {
  type    = bool
  default = false
}

variable "labels" {
  type    = map(string)
  default = {}
}

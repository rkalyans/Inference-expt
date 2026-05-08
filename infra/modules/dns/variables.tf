variable "project_id" {
  type = string
}

variable "domain" {
  type    = string
  default = "quantum-23.com"
}

variable "vpc_self_link" {
  type        = string
  description = "VPC self link for the private internal zone"
}

variable "labels" {
  type    = map(string)
  default = {}
}

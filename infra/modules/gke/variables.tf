variable "project_id" { type = string }
variable "region"     { type = string }
variable "env"        { type = string }

variable "vpc_self_link"        { type = string }
variable "subnet_self_link"     { type = string }
variable "pods_range_name"      { type = string }
variable "services_range_name"  { type = string }
variable "master_cidr"          { type = string }

variable "master_authorized_cidrs" {
  description = "Networks that may reach the public master endpoint"
  type = list(object({
    cidr = string
    name = string
  }))
  default = [
    { cidr = "0.0.0.0/0", name = "all (cloud-shell + dev laptops)" }
  ]
}

variable "deletion_protection" {
  type    = bool
  default = false
}

# ----- CPU pool -----
variable "cpu_machine_type" {
  type    = string
  default = "e2-standard-4"
}
variable "cpu_min_nodes" {
  type    = number
  default = 1
}
variable "cpu_max_nodes" {
  type    = number
  default = 3
}

# ----- GPU pool -----
variable "gpu_machine_type" {
  type        = string
  default     = "g2-standard-8"
  description = "g2-standard-8 ships with 1x NVIDIA L4 in us-east4"
}
variable "gpu_accelerator_type" {
  type    = string
  default = "nvidia-l4"
}
variable "gpu_accelerator_count" {
  type    = number
  default = 1
}
variable "gpu_min_nodes" {
  type        = number
  default     = 0
  description = "Set to 0 in dev/staging so the pool scales to zero when idle"
}
variable "gpu_max_nodes" {
  type    = number
  default = 2
}
variable "gpu_disk_size_gb" {
  type    = number
  default = 200
}

variable "labels" {
  type    = map(string)
  default = {}
}

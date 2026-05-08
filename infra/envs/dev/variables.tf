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
  description = "Full Artifact Registry image URI for the hello-world container"
  default     = "us-east4-docker.pkg.dev/inference-expt/stylist-docker/stylist-hello:latest"
}

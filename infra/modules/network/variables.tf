variable "project_id" {
  type        = string
  description = "GCP project ID"
}

variable "region" {
  type        = string
  description = "Primary region for subnets and Cloud NAT"
  default     = "us-east4"
}

variable "subnets" {
  description = "Map of env name -> CIDR config"
  type = map(object({
    primary_cidr  = string
    pods_cidr     = string
    services_cidr = string
    master_cidr   = string # /28 for GKE private control plane peering
  }))
  default = {
    dev = {
      primary_cidr  = "10.10.0.0/20"
      pods_cidr     = "10.110.0.0/16"
      services_cidr = "10.111.0.0/20"
      master_cidr   = "172.16.10.0/28"
    }
    staging = {
      primary_cidr  = "10.20.0.0/20"
      pods_cidr     = "10.120.0.0/16"
      services_cidr = "10.121.0.0/20"
      master_cidr   = "172.16.20.0/28"
    }
    prod = {
      primary_cidr  = "10.30.0.0/20"
      pods_cidr     = "10.130.0.0/16"
      services_cidr = "10.131.0.0/20"
      master_cidr   = "172.16.30.0/28"
    }
  }
}

variable "vpc_connector_cidr" {
  type        = string
  description = "/28 reserved for the Serverless VPC Access connector"
  default     = "10.8.0.0/28"
}

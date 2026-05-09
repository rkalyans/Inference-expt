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

variable "billing_account_id" {
  type        = string
  description = "Numeric billing account ID for Billing-Account-Agentic"
}

variable "owner_email" {
  type        = string
  description = "Single-owner email for alerts and budget notifications"
}

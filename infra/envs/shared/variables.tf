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

variable "alert_email" {
  type        = string
  description = "Single-owner email for alerts and budget notifications"
}

variable "deploy_langfuse" {
  type    = bool
  default = false # set true after secrets are seeded
}

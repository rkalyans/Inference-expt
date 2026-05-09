variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "billing_account_id" {
  type        = string
  description = "Numeric ID of Billing-Account-Agentic (e.g. 012345-67890A-BCDEF1)"
}

variable "owner_email" {
  type        = string
  description = "Single-owner alert email"
}

variable "budgets" {
  type        = map(string)
  description = "Per-env monthly USD budget"
  default = {
    dev     = "100"
    staging = "200"
    prod    = "500"
  }
}

variable "domain" {
  type    = string
  default = "quantum-23.com"
}

variable "deploy_langfuse" {
  type        = bool
  default     = true
}

variable "langfuse_sa_email" {
  type        = string
  default     = ""
  description = "Service account for Langfuse Cloud Run (must have Cloud SQL Client + Secret Accessor)"
}

variable "labels" {
  type    = map(string)
  default = {}
}

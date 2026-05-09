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

variable "labels" {
  type    = map(string)
  default = {}
}

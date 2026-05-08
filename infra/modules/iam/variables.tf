variable "project_id" {
  type = string
}

variable "env" {
  type        = string
  description = "shared | dev | staging | prod"
  validation {
    condition     = contains(["shared", "dev", "staging", "prod"], var.env)
    error_message = "env must be one of: shared, dev, staging, prod"
  }
}

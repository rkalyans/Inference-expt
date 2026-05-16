variable "project_id" { type = string }
variable "env"        { type = string }

variable "location" {
  type        = string
  description = "Firestore location: regional (e.g. us-east4) or multi-region (nam5, eur3)"
  default     = "us-east4"
}

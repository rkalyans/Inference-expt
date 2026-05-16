variable "project_id" { type = string }
variable "env"        { type = string }

variable "location" {
  type    = string
  default = "us-east4"
}

variable "labels" {
  type    = map(string)
  default = {}
}

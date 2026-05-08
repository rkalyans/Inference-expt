variable "project_id" {
  type = string
}

variable "secret_names" {
  type    = list(string)
  default = []
}

variable "labels" {
  type    = map(string)
  default = {}
}

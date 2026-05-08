terraform {
  backend "gcs" {
    bucket = "inference-expt-tf-state"
    prefix = "prod"
  }
}

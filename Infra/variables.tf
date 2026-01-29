variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "fuel-pipeline"
}

variable "bucket_name" {
  type    = string
  default = "fuel-pipeline-hamza-8421"
}

variable "glue_job_name" {
  type    = string
  default = "fuel_ingest"
}

variable "sns_topic_name" {
  type    = string
  default = "fuel-alerts"
}

variable "source_api_url" {
  type    = string
  default = "https://data.economie.gouv.fr/api/explore/v2.1/catalog/datasets/prix-des-carburants-en-france-flux-instantane-v2/records?limit=1000"
}

variable "raw_prefix" {
  type    = string
  default = "raw/fuel/"
}

variable "curated_prefix" {
  type    = string
  default = "curated/fuel/"
}

variable "schedule_expression" {
  type    = string
  default = "rate(1 hour)"
}

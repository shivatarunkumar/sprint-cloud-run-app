variable "project_id" {
  description = "GCP project ID."
  type        = string
}

variable "region" {
  description = "Region for the bucket, Artifact Registry and Cloud Run."
  type        = string
  default     = "europe-west2"
}

variable "bucket_name" {
  description = "Name of the upload bucket. Defaults to <project_id>-uploads."
  type        = string
  default     = ""
}

variable "service_name" {
  description = "Cloud Run service name (deployed by `make deploy`)."
  type        = string
  default     = "gcs-pubsub-app"
}

variable "artifact_repo" {
  description = "Artifact Registry Docker repository name."
  type        = string
  default     = "apps"
}

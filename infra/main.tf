locals {
  bucket_name = var.bucket_name != "" ? var.bucket_name : "${var.project_id}-uploads"

  # Cloud Run's deterministic URL, so the push subscription can be created before
  # the service is first deployed. Pub/Sub retries until the service is up.
  cloud_run_url = "https://${var.service_name}-${data.google_project.this.number}.${var.region}.run.app"
}

data "google_project" "this" {}

# ---------------------------------------------------------------------------
# APIs
# ---------------------------------------------------------------------------
resource "google_project_service" "apis" {
  for_each = toset([
    "artifactregistry.googleapis.com",
    "iam.googleapis.com",
    "pubsub.googleapis.com",
    "run.googleapis.com",
    "storage.googleapis.com",
  ])

  service            = each.value
  disable_on_destroy = false
}

# ---------------------------------------------------------------------------
# Artifact Registry (Docker images for Cloud Run)
# ---------------------------------------------------------------------------
resource "google_artifact_registry_repository" "docker" {
  location      = var.region
  repository_id = var.artifact_repo
  format        = "DOCKER"

  depends_on = [google_project_service.apis]
}

# ---------------------------------------------------------------------------
# GCS bucket + Pub/Sub topic + bucket notification
# ---------------------------------------------------------------------------
resource "google_storage_bucket" "uploads" {
  name                        = local.bucket_name
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  depends_on = [google_project_service.apis]
}

resource "google_pubsub_topic" "gcs_events" {
  name = "gcs-file-events"

  depends_on = [google_project_service.apis]
}

# The GCS service agent publishes notifications, so it needs publisher on the topic.
data "google_storage_project_service_account" "gcs" {
  depends_on = [google_project_service.apis]
}

resource "google_pubsub_topic_iam_member" "gcs_publisher" {
  topic  = google_pubsub_topic.gcs_events.id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${data.google_storage_project_service_account.gcs.email_address}"
}

resource "google_storage_notification" "uploads" {
  bucket         = google_storage_bucket.uploads.name
  topic          = google_pubsub_topic.gcs_events.id
  payload_format = "JSON_API_V1"
  event_types    = ["OBJECT_FINALIZE"]

  depends_on = [google_pubsub_topic_iam_member.gcs_publisher]
}

# ---------------------------------------------------------------------------
# Service accounts
# ---------------------------------------------------------------------------
# Identity the Cloud Run service runs as.
resource "google_service_account" "app" {
  account_id   = "gcs-pubsub-app"
  display_name = "Cloud Run runtime for ${var.service_name}"

  depends_on = [google_project_service.apis]
}

# Identity Pub/Sub uses to sign the OIDC token when pushing to Cloud Run.
resource "google_service_account" "pubsub_invoker" {
  account_id   = "pubsub-push-invoker"
  display_name = "Pub/Sub push invoker for ${var.service_name}"

  depends_on = [google_project_service.apis]
}

# Project-level so it works before the Cloud Run service exists.
resource "google_project_iam_member" "pubsub_invoker_run" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.pubsub_invoker.email}"
}

# Lets the Pub/Sub service agent mint OIDC tokens for the invoker SA.
resource "google_service_account_iam_member" "pubsub_token_creator" {
  service_account_id = google_service_account.pubsub_invoker.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"

  depends_on = [google_pubsub_topic.gcs_events]
}

# ---------------------------------------------------------------------------
# Push subscription -> Cloud Run
# ---------------------------------------------------------------------------
resource "google_pubsub_topic" "gcs_events_dlq" {
  name = "gcs-file-events-dlq"

  depends_on = [google_project_service.apis]
}

resource "google_pubsub_subscription" "gcs_events_push" {
  name                 = "gcs-file-events-push"
  topic                = google_pubsub_topic.gcs_events.id
  ack_deadline_seconds = 60

  push_config {
    push_endpoint = "${local.cloud_run_url}/pubsub/push"

    oidc_token {
      service_account_email = google_service_account.pubsub_invoker.email
      audience              = local.cloud_run_url
    }
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.gcs_events_dlq.id
    max_delivery_attempts = 10
  }

  depends_on = [
    google_project_iam_member.pubsub_invoker_run,
    google_service_account_iam_member.pubsub_token_creator,
  ]
}

# Pub/Sub service agent needs these to forward messages to the dead-letter topic.
resource "google_pubsub_topic_iam_member" "dlq_publisher" {
  topic  = google_pubsub_topic.gcs_events_dlq.id
  role   = "roles/pubsub.publisher"
  member = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

resource "google_pubsub_subscription_iam_member" "dlq_subscriber" {
  subscription = google_pubsub_subscription.gcs_events_push.id
  role         = "roles/pubsub.subscriber"
  member       = "serviceAccount:service-${data.google_project.this.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

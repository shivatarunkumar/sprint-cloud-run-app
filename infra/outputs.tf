output "bucket_name" {
  value = google_storage_bucket.uploads.name
}

output "topic" {
  value = google_pubsub_topic.gcs_events.id
}

output "subscription" {
  value = google_pubsub_subscription.gcs_events_push.id
}

output "image_repo" {
  description = "Docker repository prefix for the app image."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
}

output "app_service_account" {
  value = google_service_account.app.email
}

output "cloud_run_url" {
  description = "Expected Cloud Run URL (the push endpoint is <url>/pubsub/push)."
  value       = local.cloud_run_url
}

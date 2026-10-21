# sprint-cloud-run-app

A file uploaded to a GCS bucket sends a notification to a Pub/Sub topic. A push subscription
delivers that notification to a Spring Boot app on Cloud Run, and the app logs it.

```
GCS bucket ──(OBJECT_FINALIZE)──▶ Pub/Sub topic ──(push + OIDC)──▶ Cloud Run: POST /pubsub/push ──▶ log
```

| Folder   | Contents                                                                 |
|----------|--------------------------------------------------------------------------|
| `app/`   | Spring Boot 4.1 app (Java 17, Gradle wrapper), plus a `Dockerfile`       |
| `infra/` | Terraform: APIs, bucket, topic, bucket notification, push subscription with a DLQ, Artifact Registry, service accounts |

## Prerequisites

- Java 17, Docker, the gcloud CLI and Terraform 1.5 or later. You don't need to install Gradle; `./gradlew` downloads it.
- A GCP project with billing enabled.

## Quick start

```bash
make auth          # gcloud login + application-default creds (once)
make install       # gradle deps, terraform init, docker auth for Artifact Registry
make gcp-setup     # terraform apply: bucket, topic, subscription, registry, SAs
make deploy        # docker build (compiles jar inside) -> push -> gcloud run deploy
make upload-test   # upload a file to the bucket
make logs          # look for "Pub/Sub message received"
```

Run `make help` to see every target. The project defaults to `bigquerytarun`
and the region defaults to `europe-west2`. You can override either one, for example
`make deploy PROJECT_ID=my-proj REGION=us-central1`.

## Local development

```bash
make api-run          # http://localhost:8080
make api-test-local   # in another terminal: POST a fake GCS notification
```

## Notes

- Cloud Run is deployed with `--no-allow-unauthenticated`. Pub/Sub calls it with an OIDC token
  signed as `pubsub-push-invoker@…`, and that service account has `roles/run.invoker`.
- The push endpoint uses Cloud Run's fixed URL format
  (`https://<service>-<project-number>.<region>.run.app`). Because of this, Terraform can create
  the subscription before the first deploy. Messages sent before the deploy are retried.
- The endpoint returns 204 to acknowledge a message. After 10 failed deliveries, a message moves
  to `gcs-file-events-dlq`.
- Terraform state is stored locally in `infra/`. Move it to a GCS backend before you share this
  setup with others.
- `make gcp-destroy` removes the infrastructure, and `make undeploy` removes the Cloud Run service.

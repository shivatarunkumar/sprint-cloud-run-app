#!/usr/bin/env bash
# Checks that every resource created by `make gcp-setup` (and the Cloud Run service from
# `make deploy`) exists. Read-only. Exits non-zero if anything is missing.
# Usage: infra/check.sh <project_id> <region> <bucket> <service> <artifact_repo>
set -uo pipefail

PROJECT_ID=$1 REGION=$2 BUCKET=$3 SERVICE=$4 ARTIFACT_REPO=$5
TOPIC=gcs-file-events
DLQ_TOPIC=gcs-file-events-dlq
SUBSCRIPTION=gcs-file-events-push

missing=0

ok()   { printf "  \033[32m✔\033[0m %-24s %s\n" "$1" "$2"; }
fail() { printf "  \033[31m✘\033[0m %-24s %s\n" "$1" "$2"; missing=$((missing + 1)); }

# check <label> <gcloud args...>: passes if the describe command succeeds; prints its output.
check() {
  local label=$1; shift
  local out err
  err=$(mktemp)
  if out=$(gcloud "$@" --project "$PROJECT_ID" 2>"$err"); then
    ok "$label" "$out"
  else
    # First error line distinguishes "not found" from auth / disabled-API problems.
    fail "$label" "$(grep -m1 ERROR "$err" | cut -c1-140)"
  fi
  rm -f "$err"
}

echo "Checking resources in project $PROJECT_ID ($REGION)"

check "Bucket"               storage buckets describe "gs://$BUCKET" --format="value(name)"

# Fields are nested under "Notification Configuration", so match the topic line in the YAML output.
notif=$(gcloud storage buckets notifications list "gs://$BUCKET" --project "$PROJECT_ID" 2>/dev/null \
  | grep -m1 -o "projects/$PROJECT_ID/topics/$TOPIC$" || true)
if [[ -n $notif ]]; then ok "Bucket notification" "OBJECT_FINALIZE -> $notif"; else fail "Bucket notification" "no notification to $TOPIC"; fi

check "Topic"                pubsub topics describe "$TOPIC" --format="value(name)"
check "Dead-letter topic"    pubsub topics describe "$DLQ_TOPIC" --format="value(name)"
check "Push subscription"    pubsub subscriptions describe "$SUBSCRIPTION" --format="value(pushConfig.pushEndpoint)"
check "Artifact Registry"    artifacts repositories describe "$ARTIFACT_REPO" --location "$REGION" --format="value(name)"
check "Runtime SA"           iam service-accounts describe "gcs-pubsub-app@$PROJECT_ID.iam.gserviceaccount.com" --format="value(email)"
check "Push invoker SA"      iam service-accounts describe "pubsub-push-invoker@$PROJECT_ID.iam.gserviceaccount.com" --format="value(email)"
check "Cloud Run service"    run services describe "$SERVICE" --region "$REGION" --format="value(status.url)"

echo
if (( missing > 0 )); then
  echo "$missing resource(s) missing. Run 'make gcp-setup' (infra) and/or 'make deploy' (Cloud Run)."
  exit 1
fi
echo "All resources exist."

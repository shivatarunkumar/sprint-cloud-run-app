# GCS -> Pub/Sub -> Cloud Run (Spring Boot) demo.
# Override any variable on the command line, e.g. `make deploy REGION=us-central1`.

PROJECT_ID    ?= bigquerytarun
ifndef TAG
TAG := $(shell date +%Y%m%d-%H%M%S)
endif

REGION        ?= europe-west2
SERVICE       ?= gcs-pubsub-app
ARTIFACT_REPO ?= apps
BUCKET        ?= $(PROJECT_ID)-uploads

IMAGE      := $(REGION)-docker.pkg.dev/$(PROJECT_ID)/$(ARTIFACT_REPO)/$(SERVICE):$(TAG)
RUNTIME_SA := gcs-pubsub-app@$(PROJECT_ID).iam.gserviceaccount.com
TF_VARS    := -var project_id=$(PROJECT_ID) -var region=$(REGION) -var bucket_name=$(BUCKET) \
              -var service_name=$(SERVICE) -var artifact_repo=$(ARTIFACT_REPO)

# Gradle 9 needs JDK 17+. Pin it here so a global JAVA_HOME (e.g. Java 8) doesn't break the build.
# On macOS this is found via java_home; elsewhere pass JDK17_HOME=/path/to/jdk or keep JAVA_HOME.
JDK17_HOME ?= $(shell /usr/libexec/java_home -v 17 2>/dev/null || echo $$JAVA_HOME)

APP_DIR   := app
INFRA_DIR := infra
GRADLE    := cd $(APP_DIR) && JAVA_HOME=$(JDK17_HOME) ./gradlew

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  PROJECT_ID=$(PROJECT_ID)  REGION=$(REGION)  SERVICE=$(SERVICE)  BUCKET=$(BUCKET)"

# ---------------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------------
.PHONY: check-tools
check-tools: ## Verify java, gcloud, terraform and docker are installed
	@for t in java gcloud terraform docker; do \
		command -v $$t >/dev/null 2>&1 || { echo "Missing required tool: $$t"; exit 1; }; \
	done
	@echo "All tools present."

.PHONY: auth
auth: ## Log in to gcloud (user + application-default creds for Terraform)
	gcloud auth login
	gcloud auth application-default login
	gcloud config set project $(PROJECT_ID)

.PHONY: install
install: check-tools ## Download Gradle + app dependencies, init Terraform, configure Docker auth
	$(GRADLE) dependencies --quiet > /dev/null
	$(GRADLE) compileJava compileTestJava
	terraform -chdir=$(INFRA_DIR) init -input=false
	gcloud auth configure-docker $(REGION)-docker.pkg.dev --quiet

# ---------------------------------------------------------------------------
# App (local)
# ---------------------------------------------------------------------------
.PHONY: build
build: ## Build the jar locally + run tests (optional; Docker builds its own jar)
	$(GRADLE) build

.PHONY: test
test: ## Run unit tests
	$(GRADLE) test

.PHONY: api-run
api-run: ## Run the app locally on http://localhost:8080
	$(GRADLE) bootRun

.PHONY: api-test-local
api-test-local: ## POST a fake GCS notification to the locally running app
	@DATA=$$(printf '{"name":"hello.txt","bucket":"$(BUCKET)","contentType":"text/plain"}' | base64); \
	curl -sS -o /dev/null -w "HTTP %{http_code}\n" -X POST http://localhost:8080/pubsub/push \
		-H 'Content-Type: application/json' \
		-d "{\"message\":{\"data\":\"$$DATA\",\"attributes\":{\"eventType\":\"OBJECT_FINALIZE\",\"bucketId\":\"$(BUCKET)\",\"objectId\":\"hello.txt\"},\"messageId\":\"local-1\"},\"subscription\":\"local\"}"

# ---------------------------------------------------------------------------
# Infra (Terraform)
# ---------------------------------------------------------------------------
.PHONY: gcp-plan
gcp-plan: ## terraform plan for bucket, topic, subscription, registry, SAs
	terraform -chdir=$(INFRA_DIR) init -input=false > /dev/null
	terraform -chdir=$(INFRA_DIR) plan $(TF_VARS)

.PHONY: gcp-setup
gcp-setup: ## terraform apply: create bucket, topic, notification, push subscription, registry, SAs
	terraform -chdir=$(INFRA_DIR) init -input=false > /dev/null
	terraform -chdir=$(INFRA_DIR) apply -auto-approve $(TF_VARS)

.PHONY: gcp-check
gcp-check: ## Check that all infra resources (and the Cloud Run service) exist
	@bash $(INFRA_DIR)/check.sh $(PROJECT_ID) $(REGION) $(BUCKET) $(SERVICE) $(ARTIFACT_REPO)

.PHONY: gcp-destroy
gcp-destroy: ## terraform destroy all infra (Cloud Run service is removed by `make undeploy`)
	terraform -chdir=$(INFRA_DIR) destroy $(TF_VARS)

# ---------------------------------------------------------------------------
# Docker + Cloud Run
# ---------------------------------------------------------------------------
.PHONY: docker-build
docker-build: ## Build the linux/amd64 image (jar is compiled inside Docker)
	docker build --platform linux/amd64 -t $(IMAGE) $(APP_DIR)

.PHONY: docker-push
docker-push: docker-build ## Push the image to Artifact Registry
	docker push $(IMAGE)

.PHONY: deploy
deploy: docker-push ## Build jar + image, push, and deploy to Cloud Run
	gcloud run deploy $(SERVICE) \
		--project $(PROJECT_ID) \
		--region $(REGION) \
		--image $(IMAGE) \
		--service-account $(RUNTIME_SA) \
		--no-allow-unauthenticated \
		--port 8080 \
		--memory 512Mi \
		--max-instances 3

.PHONY: undeploy
undeploy: ## Delete the Cloud Run service
	gcloud run services delete $(SERVICE) --project $(PROJECT_ID) --region $(REGION) --quiet

.PHONY: all
all: gcp-setup deploy ## Create infra and deploy the app

# ---------------------------------------------------------------------------
# End-to-end check
# ---------------------------------------------------------------------------
.PHONY: upload-test
upload-test: ## Upload a sample file to the bucket to trigger the flow
	@echo "uploaded at $$(date)" > /tmp/gcs-pubsub-test.txt
	gcloud storage cp /tmp/gcs-pubsub-test.txt gs://$(BUCKET)/test-$$(date +%s).txt --project $(PROJECT_ID)

.PHONY: logs
logs: ## Show recent Cloud Run logs (look for "Pub/Sub message received")
	gcloud run services logs read $(SERVICE) --project $(PROJECT_ID) --region $(REGION) --limit 50

.PHONY: clean
clean: ## Remove build outputs
	$(GRADLE) clean

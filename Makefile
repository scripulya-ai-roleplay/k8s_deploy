# scripulya_deploy — run targets for the unified scripulya system.
# Two paths:
#   * Docker Compose (primary, local):  make up | down | logs | ps | reseed
#   * Kubernetes (target: kind):        make deploy-kind | status | pf | delete

APPS_DIR     ?= ..
NAMESPACE    ?= scripulya
IMAGE_TAG    ?= dev
KIND_CLUSTER ?=

# Base k8s manifests (excludes the optional ingress + mock-google).
K8S_BASE = \
	k8s/00-namespace.yaml \
	k8s/01-configmap.yaml \
	k8s/10-postgres.yaml \
	k8s/11-rabbitmq.yaml \
	k8s/12-minio.yaml \
	k8s/20-scripulya-ai.yaml \
	k8s/21-scripulya-agent.yaml

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

# ============================= Docker Compose ===============================
.PHONY: up down restart logs logs-ai logs-agent ps reseed seed-media regen-media mock-up mock-down
up:         ## Build & start the full stack (postgres, rabbitmq, ai, agent)
	docker compose up -d --build
down:       ## Stop the stack (keeps data volume)
	docker compose down
restart:    ## Restart app services (rebuild)
	docker compose up -d --build
logs:       ## Tail all logs
	docker compose logs -f
logs-ai:    ## Tail the backend logs
	docker compose logs -f scripulya-ai
logs-agent: ## Tail the LLM worker logs
	docker compose logs -f scripulya-agent
ps:         ## Show container status
	docker compose ps
reseed:     ## Wipe the DB volume and re-seed from init.sql, then restart
	docker compose down -v
	docker compose up -d --build
seed-media: ## (Re)run the MinIO scene-image seeder (skips objects already present)
	docker compose run --rm minio-init
regen-media: ## Force re-generate EVERY scene image (ignores existing objects)
	FORCE_REGENERATE_MEDIA=1 docker compose run --rm minio-init
mock-up:    ## Start the optional mock-google-api
	docker compose --profile mock-google up -d --build mock-google-api
mock-down:  ## Stop the optional mock-google-api
	docker compose --profile mock-google rm -sf mock-google-api

# ============================== Kubernetes ==================================
.PHONY: gen-secrets gen-init-sql build-images load-kind apply deploy-kind \
	apply-ingress status pf delete kind-stop kind-start kind-delete
gen-secrets:  ## Create scripulya-secrets Secret from .env
	APPS_DIR=$(APPS_DIR) NAMESPACE=$(NAMESPACE) bash scripts/gen-secrets.sh
gen-init-sql: ## Create postgres-init-sql ConfigMap from sibling init.sql
	APPS_DIR=$(APPS_DIR) NAMESPACE=$(NAMESPACE) bash scripts/gen-init-sql-cm.sh
build-images: ## Build app images from the sibling repos
	APPS_DIR=$(APPS_DIR) IMAGE_TAG=$(IMAGE_TAG) bash scripts/load-images-kind.sh
load-kind:    ## Build images and load them into kind
	APPS_DIR=$(APPS_DIR) IMAGE_TAG=$(IMAGE_TAG) bash scripts/load-images-kind.sh
apply: ## Apply namespace, then secret + init.sql, then the base manifests
	kubectl apply -f k8s/00-namespace.yaml
	@$(MAKE) --no-print-directory gen-init-sql gen-secrets
	kubectl apply -f k8s/01-configmap.yaml -f k8s/10-postgres.yaml -f k8s/11-rabbitmq.yaml -f k8s/12-minio.yaml
	kubectl apply -f k8s/20-scripulya-ai.yaml -f k8s/21-scripulya-agent.yaml
deploy-kind:  ## Full local k8s deploy: build -> load -> apply
	$(MAKE) load-kind
	$(MAKE) apply
apply-ingress: ## Apply the optional Ingress (needs an ingress controller)
	kubectl apply -f k8s/30-ingress.yaml
status:       ## Show k8s pods & services
	kubectl -n $(NAMESPACE) get pods,svc
pf:           ## Port-forward API (8000) + Rabbit mgmt UI (15672)
	NAMESPACE=$(NAMESPACE) bash scripts/port-forward.sh
delete:       ## Tear the whole namespace down (loses DB data)
	kubectl delete namespace $(NAMESPACE)
kind-stop:    ## Stop the kind cluster (frees its host ports; keeps cluster state)
	KIND_CLUSTER=$(KIND_CLUSTER) bash scripts/kind-power.sh stop
kind-start:   ## Start a previously stopped kind cluster again
	KIND_CLUSTER=$(KIND_CLUSTER) bash scripts/kind-power.sh start
kind-delete:  ## Delete the kind cluster entirely (frees ports; LOSES all state)
	KIND_CLUSTER=$(KIND_CLUSTER) bash scripts/kind-power.sh delete
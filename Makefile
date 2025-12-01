.PHONY: help build build-push deploy setup clean test lint docker-build-all docker-build-secrets-router docker-build-samples helm-package charts-dependencies

# Variables
IMAGE_NAME ?= secrets-router
IMAGE_TAG ?= latest
IMAGE_REGISTRY ?= 
NAMESPACE ?= default
DOCKERFILE ?= secrets-router/Dockerfile

help: ## Show this help message
	@echo "Usage: make [target]"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

setup: ## Setup the project (check dependencies, make scripts executable)
	@echo "Setting up project dependencies..."
	@command -v docker >/dev/null 2>&1 || { echo "Error: docker is not installed"; exit 1; }
	@command -v helm >/dev/null 2>&1 || { echo "Error: helm is not installed"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "Error: kubectl is not installed"; exit 1; }
	@echo "Setup complete!"

build: ## Build the secrets-router Docker image
	@echo "Building secrets-router image..."
	@cd secrets-router && docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .

build-push: ## Build and push the secrets-router Docker image (requires IMAGE_REGISTRY)
	@if [ -z "$(IMAGE_REGISTRY)" ]; then \
		echo "Error: IMAGE_REGISTRY must be set for build-push"; \
		exit 1; \
	fi
	@echo "Building and pushing secrets-router image..."
	@cd secrets-router && docker build -t $(IMAGE_REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG) . && docker push $(IMAGE_REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG)

deploy: ## Deploy Dapr and secrets-router to Kubernetes
	@echo "Deploying to Kubernetes..."
	@if [ -n "$(IMAGE_REGISTRY)" ]; then \
		helm upgrade --install secrets-router ./charts/secrets-router --namespace $(NAMESPACE) --create-namespace --set image.repository=$(IMAGE_REGISTRY)/$(IMAGE_NAME) --set image.tag=$(IMAGE_TAG); \
	else \
		helm upgrade --install secrets-router ./charts/secrets-router --namespace $(NAMESPACE) --create-namespace --set image.repository=$(IMAGE_NAME) --set image.tag=$(IMAGE_TAG); \
	fi

clean: ## Remove local Docker images
	@docker rmi $(IMAGE_NAME):$(IMAGE_TAG) || true
	@if [ -n "$(IMAGE_REGISTRY)" ]; then \
		docker rmi $(IMAGE_REGISTRY)/$(IMAGE_NAME):$(IMAGE_TAG) || true; \
	fi

test: ## Run tests (placeholder)
	@echo "Running tests..."
	@echo "TODO: Add tests"

lint: ## Lint Python code
	@echo "Linting Python code..."
	@if command -v ruff &> /dev/null; then \
		ruff check secrets-router/; \
	else \
		echo "ruff not installed, skipping linting"; \
	fi

# Development targets
dev-install: ## Install Python dependencies for development
	@cd secrets-router && pip install -r requirements.txt

dev-run: ## Run the service locally
	@cd secrets-router && python main.py

# Kubernetes targets
k8s-status: ## Check status of deployed resources
	@kubectl get pods -n $(NAMESPACE)
	@kubectl get pods -n dapr-system

k8s-logs: ## Show logs from secrets-router
	@kubectl logs -n $(NAMESPACE) -l app.kubernetes.io/name=secrets-router --tail=100 -f

k8s-port-forward: ## Port forward to secrets-router service
	@kubectl port-forward -n $(NAMESPACE) svc/secrets-router 8080:8080

k8s-uninstall: ## Uninstall secrets-router and Dapr
	@helm uninstall secrets-router -n $(NAMESPACE) || true
	@helm uninstall dapr -n dapr-system || true

# Docker build targets
docker-build-all: ## Build all Docker containers (secrets-router and sample services)
	@echo "Building secrets-router image..."
	@cd secrets-router && docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .
	@echo "Building sample-bash image..."
	@cd containers/sample-bash && docker build -t sample-bash:$(IMAGE_TAG) .
	@echo "Building sample-python image..."
	@cd containers/sample-python && docker build -t sample-python:$(IMAGE_TAG) .
	@echo "Building sample-node image..."
	@cd containers/sample-node && docker build -t sample-node:$(IMAGE_TAG) .
	@echo "All Docker images built successfully!"

docker-build-secrets-router: ## Build only the secrets-router Docker image
	@echo "Building secrets-router image..."
	@cd secrets-router && docker build -t $(IMAGE_NAME):$(IMAGE_TAG) .

docker-build-samples: ## Build only the sample service Docker images
	@echo "Building sample-bash image..."
	@cd containers/sample-bash && docker build -t sample-bash:$(IMAGE_TAG) .
	@echo "Building sample-python image..."
	@cd containers/sample-python && docker build -t sample-python:$(IMAGE_TAG) .
	@echo "Building sample-node image..."
	@cd containers/sample-node && docker build -t sample-node:$(IMAGE_TAG) .
	@echo "Sample service images built successfully!"

# Helm chart targets
charts-dependencies: ## Update dependencies for all Helm charts
	@echo "Updating Helm chart dependencies..."
	@cd charts/secrets-router && helm dependency update
	@cd charts/sample-service && helm dependency update
	@cd charts/umbrella && helm dependency update
	@echo "Helm dependencies updated!"

helm-package: ## Package all Helm charts
	@echo "Packaging Helm charts..."
	@mkdir -p dist/charts
	@cd charts/secrets-router && helm package . -d ../../dist/charts
	@cd charts/sample-service && helm package . -d ../../dist/charts
	@cd charts/umbrella && helm package . -d ../../dist/charts
	@echo "Helm charts packaged successfully in dist/charts!"


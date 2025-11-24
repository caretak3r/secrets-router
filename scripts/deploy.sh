#!/bin/bash
set -euo pipefail

# Deployment script for Dapr and secrets-router
# Usage: ./scripts/deploy.sh [namespace] [image-registry] [image-tag]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CHARTS_DIR="${PROJECT_ROOT}/charts"
COMPONENTS_DIR="${PROJECT_ROOT}/dapr-components"

NAMESPACE="${1:-default}"
REGISTRY="${2:-}"
IMAGE_TAG="${3:-latest}"

echo "Deploying Dapr and secrets-router to namespace: ${NAMESPACE}"
echo "Image registry: ${REGISTRY:-local}"
echo "Image tag: ${IMAGE_TAG}"

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed or not in PATH"
    exit 1
fi

# Check if helm is available
if ! command -v helm &> /dev/null; then
    echo "Error: helm is not installed or not in PATH"
    exit 1
fi

# Create namespace if it doesn't exist
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

# Add Dapr Helm repository
echo "Adding Dapr Helm repository..."
helm repo add dapr https://dapr.github.io/helm-charts/ || true
helm repo update

# Deploy Dapr control plane
echo "Deploying Dapr control plane..."
# Option 1: Use Dapr Helm chart directly
helm upgrade --install dapr dapr/dapr \
    --version 1.16.0 \
    --namespace dapr-system \
    --create-namespace \
    --wait \
    --timeout 5m \
    --set global.mtls.enabled=true \
    --set global.metrics.enabled=true \
    --set dashboard.enabled=false

# Wait for Dapr to be ready
echo "Waiting for Dapr control plane to be ready..."
kubectl wait --for=condition=ready pod \
    -l app=dapr-operator \
    -n dapr-system \
    --timeout=300s || true

kubectl wait --for=condition=ready pod \
    -l app=dapr-sentry \
    -n dapr-system \
    --timeout=300s || true

kubectl wait --for=condition=ready pod \
    -l app=dapr-placement \
    -n dapr-system \
    --timeout=300s || true

# Prepare secrets-router values
VALUES_FILE=$(mktemp)
cat > "${VALUES_FILE}" <<EOF
image:
  repository: ${REGISTRY:+${REGISTRY}/}secrets-router
  tag: ${IMAGE_TAG}
EOF

# Deploy secrets-router
echo "Deploying secrets-router..."
helm upgrade --install secrets-router "${CHARTS_DIR}/secrets-router" \
    --namespace "${NAMESPACE}" \
    --values "${VALUES_FILE}" \
    --wait \
    --timeout 5m

# Deploy Dapr components
echo "Deploying Dapr components..."
for component in "${COMPONENTS_DIR}"/*.yaml; do
    if [ -f "${component}" ]; then
        echo "Applying component: $(basename "${component}")"
        kubectl apply -f "${component}" -n "${NAMESPACE}" || true
    fi
done

# Cleanup temp file
rm -f "${VALUES_FILE}"

echo ""
echo "Deployment complete!"
echo ""
echo "To verify deployment:"
echo "  kubectl get pods -n ${NAMESPACE}"
echo "  kubectl get pods -n dapr-system"
echo ""
echo "To check secrets-router logs:"
echo "  kubectl logs -n ${NAMESPACE} -l app.kubernetes.io/name=secrets-router"
echo ""
echo "To test the service:"
echo "  kubectl port-forward -n ${NAMESPACE} svc/secrets-router 8080:8080"
echo "  curl http://localhost:8080/healthz"


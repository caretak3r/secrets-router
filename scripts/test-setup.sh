#!/bin/bash

# K8s-Secrets-Broker Test Setup Script
# Automated setup and validation for testing workflow

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🚀 K8s-Secrets-Broker Test Setup"
echo "Project Root: $PROJECT_ROOT"
echo "=================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
function log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

function log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

function log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

function check_command() {
    if ! command -v "$1" &> /dev/null; then
        log_error "$1 is required but not installed"
        exit 1
    fi
}

function verify_build() {
    local image_name=$1
    if docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "$image_name"; then
        log_info "$image_name image found"
        return 0
    else
        log_error "$image_name image not found"
        return 1
    fi
}

# 1. Prerequisites check
log_info "Checking prerequisites..."
check_command "docker"
check_command "kubectl"
check_command "helm"

# Verify Docker Desktop Kubernetes is running
if ! kubectl cluster-info &> /dev/null; then
    log_error "Kubernetes cluster is not accessible"
    exit 1
fi
log_info "Kubernetes cluster is accessible"

# 2. Build Containers
log_info "Building all containers..."

cd "$PROJECT_ROOT"

# Build secrets-router
log_info "Building secrets-router image..."
if docker build -t secrets-router:latest -f secrets-router/Dockerfile secrets-router/; then
    log_info "✅ secrets-router built successfully"
else
    log_error "❌ Failed to build secrets-router"
    exit 1
fi

# Build sample-python
log_info "Building sample-python image..."
if docker build -t sample-python:latest -f containers/sample-python/Dockerfile containers/sample-python/; then
    log_info "✅ sample-python built successfully"
else
    log_error "❌ Failed to build sample-python"
    exit 1
fi

# Build sample-node
log_info "Building sample-node image..."
if docker build -t sample-node:latest -f containers/sample-node/Dockerfile containers/sample-node/; then
    log_info "✅ sample-node built successfully"
else
    log_error "❌ Failed to build sample-node"
    exit 1
fi

# Build sample-bash
log_info "Building sample-bash image..."
if docker build -t sample-bash:latest -f containers/sample-bash/Dockerfile containers/sample-bash/; then
    log_info "✅ sample-bash built successfully"
else
    log_error "❌ Failed to build sample-bash"
    exit 1
fi

# 3. Verify builds
log_info "Verifying all images were built..."
verify_build "secrets-router:latest"
verify_build "sample-python:latest"
verify_build "sample-node:latest"
verify_build "sample-bash:latest"

# 4. Update Helm Dependencies
log_info "Updating Helm dependencies..."
cd "$PROJECT_ROOT/charts/umbrella"
if helm dependency build; then
    log_info "✅ Helm dependencies updated successfully"
else
    log_error "❌ Failed to update Helm dependencies"
    exit 1
fi

# 5. Test Chart Rendering
log_info "Testing chart rendering..."
if helm template test-release . --dry-run > /dev/null; then
    log_info "✅ Chart renders successfully"
else
    log_error "❌ Chart rendering failed"
    exit 1
fi

# 6. Clean up previous test deployments (if any)
log_info "Cleaning up any previous test deployments..."
for test_num in 1 2 3; do
    namespace="test-namespace-$test_num"
    release="test-$test_num"
    
    if helm status "$release" -n "$namespace" &> /dev/null; then
        log_warn "Uninstalling previous test-$test_num deployment..."
        helm uninstall "$release" -n "$namespace" || true
        kubectl delete namespace "$namespace" --ignore-not-found=true || true
    fi
done

# 7. Create namespaces for testing
log_info "Creating test namespaces..."
for test_num in 1 2 3; do
    namespace="test-namespace-$test_num"
    if ! kubectl get namespace "$namespace" &> /dev/null; then
        kubectl create namespace "$namespace"
        log_info "✅ Created namespace: $namespace"
    else
        log_warn "Namespace $namespace already exists"
    fi
done

# 8. Deploy Test 1 (Basic Functionality)
log_info "Deploying Test 1: Basic Functionality..."
cd "$PROJECT_ROOT"
if helm upgrade --install test-1 ./charts/umbrella \
    --namespace test-namespace-1 \
    -f testing/1/override.yaml \
    --wait --timeout=5m; then
    log_info "✅ Test 1 deployed successfully"
else
    log_error "❌ Test 1 deployment failed"
    exit 1
fi

# 9. Validate Test 1
log_info "Validating Test 1 deployment..."
if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=secrets-router -n test-namespace-1 --timeout=300s; then
    log_info "✅ Secrets router ready in test-namespace-1"
else
    log_error "❌ Secrets router not ready in test-namespace-1"
    exit 1
fi

if kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=sample-service-python -n test-namespace-1 --timeout=300s; then
    log_info "✅ Python client ready in test-namespace-1"
else
    log_error "❌ Python client not ready in test-namespace-1"
    exit 1
fi

# 10. Test connectivity
log_info "Testing service connectivity..."
PYTHON_POD=$(kubectl get pods -n test-namespace-1 -l app.kubernetes.io/name=sample-service-python -o jsonpath='{.items[0].metadata.name}')
if kubectl exec -n test-namespace-1 "$PYTHON_POD" -- curl -f -s http://test-1-secrets-router.test-namespace-1.svc.cluster.local:8080/healthz > /dev/null; then
    log_info "✅ Service connectivity test passed"
else
    log_error "❌ Service connectivity test failed"
    kubectl logs -n test-namespace-1 "$PYTHON_POD" --tail=20
    kubectl logs -n test-namespace-1 -l app.kubernetes.io/name=secrets-router --tail=20
    exit 1
fi

echo ""
echo "🎉 Test setup completed successfully!"
echo ""
echo "Next steps:"
echo "1. Deploy Test 2: helm upgrade --install test-2 ./charts/umbrella --namespace test-namespace-2 -f testing/2/override.yaml --wait"
echo "2. Deploy Test 3: helm upgrade --install test-3 ./charts/umbrella --namespace test-namespace-3 -f testing/3/override.yaml --wait"
echo "3. Run validation: kubectl get pods -n test-namespace-1,test-namespace-2,test-namespace-3"
echo "4. Check logs: kubectl logs -n test-namespace-1 -l app.kubernetes.io/name=secrets-router"
echo ""
echo "For detailed testing scenarios, see: TESTING_WORKFLOW.md"

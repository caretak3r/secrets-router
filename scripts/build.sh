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
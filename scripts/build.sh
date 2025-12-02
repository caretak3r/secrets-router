#!/bin/bash

# K8s-Secrets-Broker Build Script
# Automated build script for all containers

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Parse command line arguments
FORCE_REBUILD=false
if [[ "${1:-}" == "--help" ]] || [[ "${1:-}" == "-h" ]]; then
    echo "Usage: $0 [--force|--force]"
    echo ""
    echo "Options:"
    echo "  --force, -f    Force rebuild all images by removing existing ones first"
    echo "  --help, -h     Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0              # Build images normally (reuses layers)"
    echo "  $0 --force      # Force rebuild all images from scratch"
    exit 0
fi

if [[ "${1:-}" == "--force" ]] || [[ "${1:-}" == "-f" ]]; then
    FORCE_REBUILD=true
    shift
fi

echo "🚀 K8s-Secrets-Broker Build Script"
echo "Project Root: $PROJECT_ROOT"
if [ "$FORCE_REBUILD" = true ]; then
    echo "⚠️  Force rebuild mode enabled"
fi
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

function remove_image_if_exists() {
    local image_name=$1
    if docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "$image_name"; then
        log_info "Removing existing $image_name image..."
        if docker rmi "$image_name" 2>/dev/null || true; then
            log_info "✅ Removed $image_name"
        else
            log_warn "⚠️  Could not remove $image_name (may be in use)"
        fi
    fi
}

function build_image() {
    local image_name=$1
    local dockerfile_path=$2
    local context_path=$3
    
    log_info "Building $image_name image..."
    
    # Remove existing image if force rebuild is enabled
    if [ "$FORCE_REBUILD" = true ]; then
        remove_image_if_exists "$image_name"
    fi
    
    # Build the image
    if docker build -t "$image_name" -f "$dockerfile_path" "$context_path"; then
        log_info "✅ $image_name built successfully"
        return 0
    else
        log_error "❌ Failed to build $image_name"
        return 1
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

# Verify Docker is available
if ! docker info &> /dev/null; then
    log_error "Docker daemon is not accessible"
    exit 1
fi
log_info "Docker daemon is accessible"

# 2. Build Containers
log_info "Building all containers..."

cd "$PROJECT_ROOT"

# Build all images using the build_image function
build_image "secrets-router:latest" "secrets-router/Dockerfile" "secrets-router/"
build_image "sample-python:latest" "containers/sample-python/Dockerfile" "containers/sample-python/"
build_image "sample-node:latest" "containers/sample-node/Dockerfile" "containers/sample-node/"
build_image "sample-bash:latest" "containers/sample-bash/Dockerfile" "containers/sample-bash/"

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

echo ""
log_info "🎉 Build script completed successfully!"
if [ "$FORCE_REBUILD" = true ]; then
    log_info "⚠️  All images were force rebuilt"
fi
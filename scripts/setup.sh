#!/bin/bash
set -euo pipefail

# Setup script - installs dependencies and prepares environment
# Usage: ./scripts/setup.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "Setting up k8s-secrets-broker project..."

# Check for required tools
echo "Checking for required tools..."

MISSING_TOOLS=()

if ! command -v docker &> /dev/null; then
    MISSING_TOOLS+=("docker")
fi

if ! command -v kubectl &> /dev/null; then
    MISSING_TOOLS+=("kubectl")
fi

if ! command -v helm &> /dev/null; then
    MISSING_TOOLS+=("helm")
fi

if [ ${#MISSING_TOOLS[@]} -ne 0 ]; then
    echo "Error: Missing required tools: ${MISSING_TOOLS[*]}"
    echo "Please install the missing tools and try again."
    exit 1
fi

echo "✓ All required tools are installed"

# Check Docker daemon
if ! docker info &> /dev/null; then
    echo "Error: Docker daemon is not running"
    exit 1
fi

echo "✓ Docker daemon is running"

# Check kubectl connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo "Warning: kubectl cannot connect to cluster"
    echo "Make sure your kubeconfig is configured correctly"
else
    echo "✓ kubectl can connect to cluster"
fi

# Make scripts executable
chmod +x "${SCRIPT_DIR}"/*.sh

echo ""
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Build the Docker image:"
echo "     ./scripts/build-image.sh [tag] [registry]"
echo ""
echo "  2. Deploy to Kubernetes:"
echo "     ./scripts/deploy.sh [namespace] [registry] [tag]"
echo ""
echo "  3. Or use the Makefile:"
echo "     make build"
echo "     make deploy"


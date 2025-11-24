#!/bin/bash
set -euo pipefail

# Build script for secrets-router Docker image
# Usage: ./scripts/build-image.sh [tag] [registry]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SECRETS_ROUTER_DIR="${PROJECT_ROOT}/secrets-router"

TAG="${1:-latest}"
REGISTRY="${2:-}"

IMAGE_NAME="secrets-router"
FULL_IMAGE_NAME="${IMAGE_NAME}:${TAG}"

if [ -n "${REGISTRY}" ]; then
    FULL_IMAGE_NAME="${REGISTRY}/${IMAGE_NAME}:${TAG}"
fi

echo "Building Docker image: ${FULL_IMAGE_NAME}"
echo "Working directory: ${SECRETS_ROUTER_DIR}"

cd "${SECRETS_ROUTER_DIR}"

docker build \
    --tag "${FULL_IMAGE_NAME}" \
    --file Dockerfile \
    .

echo "Successfully built image: ${FULL_IMAGE_NAME}"

# Optionally push to registry
if [ -n "${REGISTRY}" ] && [ "${3:-}" = "--push" ]; then
    echo "Pushing image to registry: ${FULL_IMAGE_NAME}"
    docker push "${FULL_IMAGE_NAME}"
    echo "Successfully pushed image: ${FULL_IMAGE_NAME}"
fi


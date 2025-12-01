#!/bin/bash
# Setup script for Test Scenario 1
# Creates Kubernetes secrets for testing the new secrets configuration

set -e

NAMESPACE="test-namespace-1"
RELEASE_NAME="test-1"

echo "🔧 Setting up Test Scenario 1: New Secrets Configuration"
echo "Namespace: $NAMESPACE"
echo "Release: $RELEASE_NAME"

# Create namespace
echo "📦 Creating namespace: $NAMESPACE"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Create test secrets in the namespace
echo "🔐 Creating test secrets..."

# RDS credentials secret
kubectl create secret generic k8s-rds-credentials \
  --from-literal=host="test-db.example.com" \
  --from-literal=port="5432" \
  --from-literal=username="testuser" \
  --from-literal=password="testpass123" \
  --from-literal=database="testdb" \
  --namespace $NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

# API keys secret
kubectl create secret generic k8s-api-keys \
  --from-literal=api-key="sk-test-api-key-12345" \
  --from-literal=api-secret="secret-api-key-67890" \
  --from-literal=webhook-url="https://api.example.com/webhook" \
  --namespace $NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

# Redis password secret
kubectl create secret generic k8s-redis-password \
  --from-literal=password="redis-secret-password-abc" \
  --from-literal=host="redis.example.com" \
  --from-literal=port="6379" \
  --namespace $NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Test secrets created successfully in namespace: $NAMESPACE"
echo ""
echo "📋 Created secrets:"
echo "  - k8s-rds-credentials (host, port, username, password, database)"
echo "  - k8s-api-keys (api-key, api-secret, webhook-url)"
echo "  - k8s-redis-password (password, host, port)"
echo ""
echo "🚀 Ready to deploy with:"
echo "  helm upgrade --install $RELEASE_NAME ./charts/umbrella --namespace $NAMESPACE -f testing/1/override.yaml"

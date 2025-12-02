#!/bin/bash
# Setup script for Test Scenario 1
# Creates Kubernetes secrets for testing the new secrets configuration

set -e

NAMESPACE="demo"
RELEASE_NAME="control-plane"

echo "🔧 Setting up Demo: New Secrets Configuration"
echo "Namespace: $NAMESPACE"
echo "Release: $RELEASE_NAME"

# Create namespace
echo "📦 Creating namespace: $NAMESPACE"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Create test secrets in the namespace
echo "🔐 Creating demo secrets..."

# RDS credentials secret
kubectl create secret generic rds-credentials \
  --from-literal=host="test-db.example.com" \
  --from-literal=port="5432" \
  --from-literal=username="testuser" \
  --from-literal=password="testpass123" \
  --from-literal=database="testdb" \
  --namespace $NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

# API keys secret
kubectl create secret generic api-keys \
  --from-literal=api-key="sk-test-api-key-12345" \
  --from-literal=api-secret="secret-api-key-67890" \
  --from-literal=webhook-url="https://api.example.com/webhook" \
  --namespace $NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

# Redis password secret
kubectl create secret generic redis-password \
  --from-literal=password="redis-secret-password-abc" \
  --from-literal=host="redis.example.com" \
  --from-literal=port="6379" \
  --namespace $NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic shell-password \
  --from-literal=password="shell-secret-password-abc" \
  --namespace $NAMESPACE \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Test secrets created successfully in namespace: $NAMESPACE"
echo ""
echo "📋 Created secrets:"
echo "  - rds-credentials (host, port, username, password, database)"
echo "  - api-keys (api-key, api-secret, webhook-url)"
echo "  - redis-password (password, host, port)"
echo "  - shell-password (password)"
echo ""
echo "🚀 Ready to deploy with:"
echo "  helm upgrade --install $RELEASE_NAME ./charts/umbrella --namespace $NAMESPACE -f testing/override.yaml"

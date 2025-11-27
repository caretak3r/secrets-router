#!/bin/bash

set -e

# Helper script to deploy and test the k8s-secrets-broker

# Set variables
NAMESPACE="test-namespace"
OVERRIDE_FILE="override-20251127.yaml"

echo "🚀 Starting k8s-secrets-broker deployment..."
echo "Namespace: $NAMESPACE"

# Check if we can connect to cluster
if ! kubectl cluster-info &>/dev/null; then
    echo "❌ Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "✅ Connected to Kubernetes cluster"

# Install secrets-router with Helm (will create namespace)
echo "📦 Installing secrets-router with Helm..."
helm install secrets-broker ./charts/umbrella \
    --create-namespace \
    --namespace $NAMESPACE \
    --wait \
    --timeout 10m \
    -f $OVERRIDE_FILE

if [ $? -eq 0 ]; then
    echo "✅ Helm installation successful"
else
    echo "❌ Helm installation failed"
    exit 1
fi

# Wait for pods to be ready
echo "⏳ Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=secrets-router -n $NAMESPACE --timeout=300s
kubectl wait --for=condition=ready pod -l app=dapr-sidecar-injector -n dapr-system --timeout=300s

# Create and install sample secrets (after namespace creation)
echo "📝 Creating sample secrets..."
kubectl apply -f sample-secrets.yaml

# Install sample app
echo "🚀 Deploying sample app..."
kubectl apply -f sample-app-deployment.yaml

# Wait for sample app to be ready
echo "⏳ Waiting for sample app to be ready..."
kubectl wait --for=condition=ready pod -l app=sample-app -n sample-app --timeout=180s

# Test the secrets-router service
echo "🧪 Testing secrets-router functionality..."

# Test 1: Secret from same namespace as secrets-router
echo "Test 1: Getting secret from test-namespace (same as secrets-router)..."
kubectl exec -n sample-app deployment/sample-app -- curl -s "http://secrets-router.test-namespace.svc.cluster.local:8080/secrets/test-namespace-secret/password?namespace=test-namespace" || echo "❌ Test 1 failed"

# Test 2: Secret from default namespace  
echo "Test 2: Getting secret from default namespace (cross-namespace)..."
kubectl exec -n sample-app deployment/sample-app -- curl -s "http://secrets-router.test-namespace.svc.cluster.local:8080/secrets/default-namespace-secret/api-key?namespace=default" || echo "❌ Test 2 failed"

# Test 3: Health check
echo "Test 3: Health check..."
kubectl exec -n $NAMESPACE deployment/secrets-router -- curl -s http://localhost:8080/healthz || echo "❌ Health check failed"

echo "✅ Deployment and testing complete!"
echo "📊 Check status:"
echo "  kubectl get pods -n $NAMESPACE"
echo "  kubectl get pods -n sample-app"
echo "  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=secrets-router"

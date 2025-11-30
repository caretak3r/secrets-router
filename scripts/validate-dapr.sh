#!/bin/bash

# Dapr Installation Validation Script
set -e

NAMESPACE=${1:-default}
RELEASE_NAME=${2:-secrets-router}

echo "🔍 Validating Dapr installation and components..."

# Check if Dapr is installed on the cluster
if ! kubectl cluster-info | grep -q "dapr-system"; then
    echo "⚠️  Dapr system not found. Installing Dapr..."
    dapr init -k --wait
else
    echo "✅ Dapr system components detected"
fi

# Check if namespace has Dapr injection enabled
echo "🔍 Checking namespace: $NAMESPACE"
NAMESPACE_INJECTION=$(kubectl get namespace $NAMESPACE -o jsonpath='{.metadata.annotations.dapr\.io/sidecar-injection}' 2>/dev/null || echo "not found")

if [ "$NAMESPACE_INJECTION" = "enabled" ]; then
    echo "✅ Namespace has Dapr sidecar injection enabled"
elif [ "$NAMESPACE_INJECTION" = "not found" ]; then
    echo "⚠️  Enabling Dapr sidecar injection on namespace..."
    kubectl annotate namespace $NAMESPACE dapr.io/sidecar-injection=enabled --overwrite
else
    echo "ℹ️  Namespace injection status: $NAMESPACE_INJECTION"
fi

# Check for component conflicts
echo "🔍 Checking for component conflicts..."
COMPONENTS=$(kubectl get components -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || echo "")

if [ -n "$COMPONENTS" ]; then
    echo "📦 Found components in namespace: $COMPONENTS"
    
    # Check for conflicting kubernetes component
    if echo "$COMPONENTS" | grep -q "^kubernetes$"; then
        echo "⚠️  Found conflicting 'kubernetes' component. Removing..."
        kubectl delete component kubernetes -n $NAMESPACE || true
        echo "✅ Removed conflicting component"
    fi
fi

echo "🎯 Dapr validation complete. Ready for deployment:"

# Show status
kubectl get pods -n $NAMESPACE -l app.kubernetes.io/component=secrets-router 2>/dev/null || echo "ℹ️  No secrets-router pods found (expected before deployment)"
kubectl get components -n $NAMESPACE 2>/dev/null || echo "ℹ️  No components found yet"

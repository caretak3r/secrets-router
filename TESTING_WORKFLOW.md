# K8s-Secrets-Broker Testing Workflow

## Overview
This document provides a comprehensive step-by-step testing workflow for the k8s-secrets-broker project from a clean state, including container builds, Helm chart setup, deployment, and end-to-end validation.

## Prerequisites
- Docker Desktop with Kubernetes enabled
- Helm 3.x installed
- kubectl configured to use Docker Desktop cluster
- Project root: `/Users/rohit/Documents/questionable/k8s-secrets-broker`

## Step 1: Build All Containers

### 1.1 Build Secrets Router Service
```bash
cd /Users/rohit/Documents/questionable/k8s-secrets-broker

# Build the secrets-router image
docker build -t secrets-router:latest -f secrets-router/Dockerfile secrets-router/

# Verify the build
docker images | grep secrets-router
```

### 1.2 Build Sample Python Client
```bash
# Build sample Python client
docker build -t sample-python:latest -f containers/sample-python/Dockerfile containers/sample-python/

# Verify the build
docker images | grep sample-python
```

### 1.3 Build Sample Node.js Client
```bash
# Build sample Node.js client
docker build -t sample-node:latest -f containers/sample-node/Dockerfile containers/sample-node/

# Verify the build
docker images | grep sample-node
```

### 1.4 Build Sample Bash Client
```bash
# Build sample Bash client
docker build -t sample-bash:latest -f containers/sample-bash/Dockerfile containers/sample-bash/

# Verify the build
docker images | grep sample-bash
```

## Step 2: Helm Chart Setup and Dependency Management

### 2.1 Chart Structure Overview
```
charts/
├── umbrella/          # Main deployment chart with dependencies
├── secrets-router/    # Secrets router service chart
└── sample-service/    # Sample client applications chart
```

### 2.2 Update Helm Dependencies
```bash
cd /Users/rohit/Documents/questionable/k8s-secrets-broker/charts/umbrella

# Build/update dependencies
helm dependency build

# Alternative: update dependencies
helm dependency update

# Verify Chart.lock is updated
cat Chart.lock
```

### 2.3 Verify Chart Rendering
```bash
# Test chart rendering without installing
helm template test-release . --dry-run

# Check for any rendering errors
# Fix any issues discovered in charts before proceeding
```

## Step 3: Test Scenarios Setup

The project includes 3 test scenarios with isolated namespaces:
- Test 1: Basic functionality (test-namespace-1)
- Test 2: Multi-namespace access (test-namespace-2)
- Test 3: AWS Secrets Manager integration (test-namespace-3)

### 3.1 Test Override Files
Each test has an `override.yaml` file in `testing/N/` directory with:
- Secrets router configuration
- Sample service client enabling/disabling
- Environment variables for service discovery
- Namespace isolation

## Step 4: Deployment Workflow

### 4.1 General Deployment Pattern
```bash
# Template for each test:
helm upgrade --install <release-name> ./charts/umbrella \
  --create-namespace \
  --namespace <test-namespace> \
  -f testing/<test-number>/override.yaml
```

### 4.2 Deploy Test 1: Basic Functionality
```bash
cd /Users/rohit/Documents/questionable/k8s-secrets-broker

# Deploy test 1 with Python client only
helm upgrade --install test-1 ./charts/umbrella \
  --create-namespace \
  --namespace test-namespace-1 \
  -f testing/1/override.yaml

# Wait for deployment (2-3 minutes)
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=secrets-router -n test-namespace-1 --timeout=300s
```

### 4.3 Deploy Test 2: Multi-namespace Access
```bash
# Deploy test 2 with Python and Bash clients
helm upgrade --install test-2 ./charts/umbrella \
  --create-namespace \
  --namespace test-namespace-2 \
  -f testing/2/override.yaml

# Wait for deployment
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=secrets-router -n test-namespace-2 --timeout=300s
```

### 4.4 Deploy Test 3: AWS Integration (THIS WON'T WORK LOCALLY - so skip for now). 
```bash
# Deploy test 3 with all clients
helm upgrade --install test-3 ./charts/umbrella \
  --create-namespace \
  --namespace test-namespace-3 \
  -f testing/3/override.yaml

# Wait for deployment
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=secrets-router -n test-namespace-3 --timeout=300s
```

## Step 5: Validation and Testing

### 5.1 Health Check All Deployments
```bash
# Check all test namespaces
for ns in test-namespace-1 test-namespace-2 test-namespace-3; do
  echo "=== Namespace: $ns ==="
  kubectl get pods -n $ns
  kubectl get services -n $ns
done
```

### 5.2 Secrets Router Service Validation
```bash
# Test 1 secrets router
echo "=== Test 1: Secrets Router Logs ==="
kubectl logs -n test-namespace-1 -l app.kubernetes.io/name=secrets-router --tail=50

# Test health endpoint
kubectl port-forward -n test-namespace-1 svc/test-1-secrets-router 8080:8080 &
sleep 5
curl http://localhost:8080/healthz
curl http://localhost:8080/readyz  
pkill -f "kubectl port-forward" || true
```

### 5.3 Client Application Testing
```bash
# Check Python client logs (Test 1)
echo "=== Test 1: Python Client Logs ==="
kubectl logs -n test-namespace-1 -l app.kubernetes.io/name=sample-service-python --tail=50

# Check Python and Bash client logs (Test 2)
echo "=== Test 2: Python and Bash Client Logs ==="
kubectl logs -n test-namespace-2 -l app.kubernetes.io/name=sample-service-python --tail=50
kubectl logs -n test-namespace-2 -l app.kubernetes.io/name=sample-service-bash --tail=50

# Check all client logs (Test 3)
echo "=== Test 3: All Client Logs ==="
kubectl logs -n test-namespace-3 -l app.kubernetes.io/name=sample-service-python --tail=50
kubectl logs -n test-namespace-3 -l app.kubernetes.io/name=sample-service-bash --tail=50
kubectl logs -n test-namespace-3 -l app.kubernetes.io/name=sample-service-node --tail=50
```

### 5.4 Service Discovery and Connectivity Testing
```bash
# Test inter-service communication in Test 1
# Exec into Python client pod and test connection to secrets router
PYTHON_POD=$(kubectl get pods -n test-namespace-1 -l app.kubernetes.io/name=sample-service-python -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n test-namespace-1 $PYTHON_POD -- curl -s http://test-1-secrets-router.test-namespace-1.svc.cluster.local:8080/healthz
```

## Step 6: Troubleshooting Guide

### 6.1 Common Issues and Solutions

#### Image Pull Issues
```bash
# If pods show ImagePullBackOff, check images are built locally
docker images | grep -E "(secrets-router|sample-)"

# Use local images with imagePullPolicy: Never (already in override files)
```

#### Pod Not Starting
```bash
# Check pod events
kubectl describe pod -n <namespace> <pod-name>

# Check logs for errors
kubectl logs -n <namespace> <pod-name> --previous
```

#### Service Discovery Issues
```bash
# Verify service DNS resolution
kubectl exec -n <namespace> <pod-name> -- nslookup <service-name>.<namespace>.svc.cluster.local

# Check service endpoints
kubectl get endpoints -n <namespace>
```

#### Dapr Integration Issues
```bash
# Check Dapr control plane
kubectl get pods -n dapr-system

# Check Dapr sidecar injection
kubectl get pods -n <namespace> -o wide | grep dapr

# Check Dapr logs
kubectl logs -n <namespace> <pod-name> -c daprd
```

### 6.2 Reset and Cleanup
```bash
# Clean up all test namespaces
helm uninstall test-1 -n test-namespace-1
helm uninstall test-2 -n test-namespace-2 
helm uninstall test-3 -n test-namespace-3

# Delete namespaces
kubectl delete namespace test-namespace-1 test-namespace-2 test-namespace-3

# Remove local images (optional)
docker rmi secrets-router:latest
docker rmi sample-python:latest
docker rmi sample-node:latest
docker rmi sample-bash:latest
```

## Step 7: End-to-End Test Scenarios

### 7.1 Test Scenario 1: Basic Secret Retrieval
```bash
# Create a test secret in test-namespace-1
kubectl create secret generic database-credentials \
  --from-literal=password=test123 \
  --from-literal=username=admin \
  -n test-namespace-1

# Test secret retrieval via Python client
PYTHON_POD=$(kubectl get pods -n test-namespace-1 -l app.kubernetes.io/name=sample-service-python -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n test-namespace-1 $PYTHON_POD -- python3 -c "
import httpx
response = httpx.get('http://test-1-secrets-router.test-namespace-1.svc.cluster.local:8080/secrets/database-credentials/password')
print(f'Secret retrieved: {response.text}')
"
```

### 7.2 Test Scenario 2: Cross-Namespace Access
```bash
# Create secret in shared-secrets namespace
kubectl create namespace shared-secrets
kubectl create secret generic app-config \
  --from-literal=api-key=demo-key-123 \
  -n shared-secrets

# Test access from test-namespace-2
PYTHON_POD=$(kubectl get pods -n test-namespace-2 -l app.kubernetes.io/name=sample-service-python -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n test-namespace-2 $PYTHON_POD -- curl -s "http://test-2-secrets-router.test-namespace-2.svc.cluster.local:8080/secrets/app-config/api-key?namespace=shared-secrets"
```

### 7.3 Test Scenario 3: Client Connectivity Validation
```bash
# Verify all clients can connect to secrets router
for ns in test-namespace-3; do
  echo "=== Testing in $ns ==="
  
  # Python client
  PYTHON_POD=$(kubectl get pods -n $ns -l app.kubernetes.io/name=sample-service-python -o jsonpath='{.items[0].metadata.name}')
  kubectl exec -n $ns $PYTHON_POD -- curl -s "http://test-3-secrets-router.$ns.svc.cluster.local:8080/healthz"
  
  # Bash client  
  BASH_POD=$(kubectl get pods -n $ns -l app.kubernetes.io/name=sample-service-bash -o jsonpath='{.items[0].metadata.name}')
  kubectl exec -n $ns $BASH_POD -- curl -s "http://test-3-secrets-router.$ns.svc.cluster.local:8080/healthz"
  
  # Node client
  NODE_POD=$(kubectl get pods -n $ns -l app.kubernetes.io/name=sample-service-node -o jsonpath='{.items[0].metadata.name}')
  kubectl exec -n $ns $NODE_POD -- curl -s "http://test-3-secrets-router.$ns.svc.cluster.local:8080/healthz"
done
```

## Success Criteria
- All containers build successfully
- Helm charts render without errors
- All 3 test deployments complete successfully
- All pods reach Running state with Ready condition
- Secrets router responds to health checks
- Sample clients can communicate with secrets router
- Service discovery works correctly in all test namespaces
- Secret retrieval functionality works end-to-end

## Performance Notes
- Allow 2-3 minutes per test deployment for pod initialization
- Dapr sidecar injection adds ~30-60 seconds startup time
- Image pull policy set to Never to avoid registry delays
- Use `kubectl wait` commands to automate readiness checks

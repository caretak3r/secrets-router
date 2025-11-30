# K8s-Secrets-Broker Testing Workflow with Automated Orchestrator

## Overview
This document provides a comprehensive testing workflow for the k8s-secrets-broker project using the automated test orchestrator approach. The orchestrator manages container builds, Helm chart setup, deployment, and end-to-end validation with minimal override configurations.

## Test Orchestrator Philosophy

The kubernetes-secrets-router-test-orchestrator provides automated end-to-end testing with these key principles:

1. **Container Build Optimization**: Build containers only when source code changes
2. **Minimal Override Files**: Override files contain ONLY values that differ from base chart defaults
3. **Helm Dependency Management**: Update dependencies only when source code or templating changes  
4. **Namespace Isolation**: Each test runs in isolated namespaces
5. **Health Validation**: Comprehensive health check validation with startupProbe support
6. **No Chart Modification**: Original Helm charts are preserved unless fixing bugs

## Prerequisites
- Docker Desktop with Kubernetes enabled
- Helm 3.x installed
- kubectl configured to use Docker Desktop cluster
- Project root: `/Users/rohit/Documents/questionable/k8s-secrets-broker`

## Test Orchestrator Workflow

### Test Scenarios

The orchestrator executes exactly two test scenarios:

#### Test 1: Same Namespace Success Case
- **Objective**: Deploy secrets-router, Dapr, and sample services in the same namespace
- **Expected Result**: All services communicate successfully within the shared namespace
- **Service Discovery**: Uses in-cluster DNS: `<service-name>.<namespace>.svc.cluster.local`

#### Test 2: Cross-Namespace Failure Case  
- **Objective**: Split deployment across namespaces to demonstrate failure modes
- **Configuration**: secrets-router and Dapr in one namespace (test-2-router), sample services in another (test-2-clients)
- **Expected Result**: Cross-namespace communication failures demonstrating namespace scoping requirements

### Critical Override File Methodology

**Before writing override.yaml, ALWAYS analyze base values.yaml files first** to identify the minimal set of required overrides.

#### Analysis Example:
```bash
# Base secrets-router/values.yaml defaults:
- image.pullPolicy: "Always"       # Override needed: "Never" for local images
- dapr.enabled: true              # No override needed (same value)
- secretStores.aws.enabled: true  # Override needed: false for testing
- healthChecks.startupProbe.enabled: true  # No override needed (new feature)

# Base sample-service/values.yaml defaults:
- clients.*.enabled: true         # Override only if disabling
- clients.*.image.pullPolicy: "Never"   # No override needed (same value)
- clients.*.env defaults to dapr-control-plane namespace
```

#### Minimal Override Structure:
```yaml
# ONLY values that DIFFER from base chart defaults
secrets-router:
  image:
    pullPolicy: Never  # Override base "Always"
  secretStores:
    aws:
      enabled: false   # Override base "true"
    stores:
      kubernetes-secrets:
        namespaces:
          - test-namespace-1  # Test-specific config

sample-service:
  clients:
    python:
      env:
        SECRETS_ROUTER_URL: "http://test-1-secrets-router.test-namespace-1.svc.cluster.local:8080"  # Different from default
        TEST_SECRET_NAME: "sample-secret"    # Same as default - could be omitted
        TEST_NAMESPACE: "test-namespace-1"     # Different from default "dapr-control-plane"
    node:
      enabled: false    # Override base "true"
```

**Principle**: If the value is the same as in the base chart, DO NOT include it in the override.yaml!

## Step 1: Orchestrated Container Building

The test orchestrator optimizes container building by building only when source code has changed:

### 1.1 Build Automation
```bash
cd /Users/rohit/Documents/questionable/k8s-secrets-broker

# The orchestrator detects source changes and builds selectively:
# Build secrets-router service only if source code changed
docker build -t secrets-router:latest -f secrets-router/Dockerfile secrets-router/

# Build sample client containers only if Dockerfiles changed
docker build -t sample-python:latest -f containers/sample-python/Dockerfile containers/sample-python/
docker build -t sample-node:latest -f containers/sample-node/Dockerfile containers/sample-node/
docker build -t sample-bash:latest -f containers/sample-bash/Dockerfile containers/sample-bash/

# Or use Makefile for all containers
make build IMAGE_TAG=latest
```

### 1.2 Build Verification
```bash
# Verify all required images exist
docker images | grep secrets-router
docker images | grep sample-
```

## Step 2: Helm Chart Dependency Management

The orchestrator manages Helm dependencies only when source code or templating changes:

### 2.1 Umbrella Chart Structure
```
charts/umbrella/
├── Chart.yaml        # Dependencies: dapr, secrets-router, sample-service
├── Chart.lock        # Pinned dependency versions  
├── values.yaml       # High-level enable/disable flags
└── templates/        # Umbrella templates
```

### 2.2 Dependency Updates (Conditional)
```bash
cd /Users/rohit/Documents/questionable/k8s-secrets-broker/charts/umbrella

# Only update dependencies if source code or templating changed:
helm dependency build
# OR
helm dependency update

# Verify Chart.lock reflects current dependencies
cat Chart.lock
```

### 2.3 Chart Rendering Verification
```bash
# Test chart rendering without installing
helm template test-release . --dry-run -f testing/1/override.yaml

# Check for rendering errors before deployment
```

## Step 3: Test Scenario Deployment with Orchestrator

The orchestrator manages deployment using minimal override configurations:

### 3.1 Deployment Pattern
```bash
# Template for each test scenario:
helm upgrade --install <release-name> ./charts/umbrella \
  --create-namespace \
  --namespace <test-namespace> \
  -f testing/<test-number>/override.yaml
```

### 3.2 Test 1: Same Namespace Success Case
```bash
cd /Users/rohit/Documents/questionable/k8s-secrets-broker

# Deploy all services in same namespace with minimal overrides
helm upgrade --install test-1 ./charts/umbrella \
  --create-namespace \
  --namespace test-namespace-1 \
  -f testing/1/override.yaml

# Wait for startupProbe to allow Dapr sidecar initialization (up to 5 minutes)
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=secrets-router -n test-namespace-1 --timeout=300s
```

### 3.3 Test 2: Cross-Namespace Demonstration
```bash
# Deploy to demonstrate cross-namespace failure modes
helm upgrade --install test-2 ./charts/umbrella \
  --create-namespace \
  --namespace test-namespace-2 \
  -f testing/2/override.yaml

# Wait for deployment and observe communication patterns
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=secrets-router -n test-namespace-2 --timeout=300s
```

## Step 4: Health Check Validation with Enhanced Probes

The orchestrator validates deployments using comprehensive health checks that include the new startupProbe configuration:

### 4.1 Enhanced Health Check Configuration
```yaml
# Health checks configured in charts/secrets-router/values.yaml:
healthChecks:
  liveness:
    enabled: true
    path: /healthz
    initialDelaySeconds: 30
    periodSeconds: 10
  readiness:
    enabled: true
    path: /readyz
    initialDelaySeconds: 30
    periodSeconds: 5
    timeoutSeconds: 5
    failureThreshold: 3
  startupProbe:
    enabled: true
    path: /healthz
    initialDelaySeconds: 10
    periodSeconds: 10
    timeoutSeconds: 5
    failureThreshold: 30  # Extended for Dapr timing issues
```

### 4.2 Health Status Verification
```bash
# Check all test namespaces and pod status
for ns in test-namespace-1 test-namespace-2; do
  echo "=== Namespace: $ns ==="
  kubectl get pods -n $ns
  kubectl get services -n $ns
  # Check pod health status
  kubectl get pods -n $ns -o wide
done
```

### 4.3 Secrets Router Service Health Validation
```bash
# Test 1 secrets router health endpoints
echo "=== Test 1: Secrets Router Health Checks ==="
kubectl logs -n test-namespace-1 -l app.kubernetes.io/name=secrets-router --tail=50

# Test health endpoints directly via port-forward
kubectl port-forward -n test-namespace-1 svc/test-1-secrets-router 8080:8080 &
sleep 5

# Test liveness endpoint (/healthz)
curl http://localhost:8080/healthz

# Test readiness endpoint (/readyz) - checks Dapr connectivity
curl http://localhost:8080/readyz
pkill -f "kubectl port-forward" || true

# Verify startupProbe allowed adequate time for Dapr initialization
kubectl get pods -n test-namespace-1 -o yaml | grep -A 10 startupProbe
```

### 4.4 Client Application Testing and Service Discovery
```bash
# Check Python client logs (Test 1) - verify service discovery works
echo "=== Test 1: Python Client Service Discovery ==="
kubectl logs -n test-namespace-1 -l app.kubernetes.io/name=sample-service-python --tail=50

# Check connectivity from client pods to secrets router
PYTHON_POD=$(kubectl get pods -n test-namespace-1 -l app.kubernetes.io/name=sample-service-python -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n test-namespace-1 $PYTHON_POD -- \
  curl -s "http://test-1-secrets-router.test-namespace-1.svc.cluster.local:8080/healthz"

# Test cross-namespace failures in Test 2
echo "=== Test 2: Cross-Namespace Service Discovery ==="
PYTHON_POD=$(kubectl get pods -n test-namespace-2 -l app.kubernetes.io/name=sample-service-python -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n test-namespace-2 $PYTHON_POD -- \
  curl -s "http://test-2-secrets-router.test-namespace-2.svc.cluster.local:8080/healthz" || echo "Expected failure: Cross-namespace communication"
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

## Success Criteria with Enhanced Health Validation

- All containers build successfully with source change detection
- Helm charts render without errors using minimal override configurations
- Both test deployments complete successfully using the orchestrator approach
- All pods reach Running status with Ready condition, supported by startupProbe configuration
- Secrets router responds to health checks (/healthz, /readyz) with proper Dapr connectivity
- Sample clients can communicate with secrets router using in-cluster DNS
- Service discovery works correctly in same-namespace scenario (Test 1)
- Cross-namespace failure modes are properly demonstrated (Test 2)
- Override files contain only values that differ from base chart defaults
- Dapr sidecar injection and mTLS establishment verified via readiness probe

## Performance and Health Notes

- Allow 2-5 minutes per test deployment for pod initialization due to startupProbe configuration
- Dapr sidecar injection adds ~30-60 seconds startup time (addressed by startupProbe with 30 failure threshold)
- Image pull policy set to Never to avoid registry delays in local testing
- Use `kubectl wait` commands to automate readiness checks with extended timeouts
- StartupProbe ensures containers have adequate time for Dapr sidecar connection before Kubernetes marks them as failed
- Enhanced health checks prevent premature restarts during Dapr initialization

## Orchestrator Benefits

The automated test orchestrator provides these advantages over manual testing:

1. **Optimized Builds**: Containers built only when source changes detected
2. **Minimal Overrides**: Prevents configuration redundancy by analyzing base chart values
3. **Dependency Management**: Helm dependencies updated only when templating changes
4. **Health Focus**: Comprehensive health validation including startupProbe timing
5. **Namespace Isolation**: Clean test environment separation
6. **No Chart Pollution**: Original charts preserved unless fixing bugs
7. **Service Discovery Validation**: Proper DNS connectivity testing
8. **Failure Mode Documentation**: Clear demonstration of cross-namespace limitations

The orchestrator approach ensures consistent, repeatable testing while maintaining the integrity of the base Helm charts and minimizing configuration overhead.

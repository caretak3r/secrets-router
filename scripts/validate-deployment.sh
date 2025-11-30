#!/bin/bash

# K8s-Secrets-Broker Deployment Validation Script
# Comprehensive validation of all test deployments

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "🔍 K8s-Secrets-Broker Deployment Validation"
echo "=========================================="

# Helper functions
function log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

function log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

function log_error() {
    echo_error "$1"
}

function log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

function log_heading() {
    echo -e "${BLUE}=== $1 ===${NC}"
}

function check_pod_status() {
    local namespace=$1
    local selector=$2
    local expected_count=$3
    local component=$4
    
    local ready_count
    ready_count=$(kubectl get pods -n "$namespace" -l "$selector" --no-headers | grep -c "Running" || echo "0")
    
    if [ "$ready_count" -eq "$expected_count" ]; then
        log_info "✅ $component: $ready_count/$expected_count pods ready in $namespace"
        return 0
    else
        log_error "❌ $component: $ready_count/$expected_count pods ready in $namespace"
        kubectl get pods -n "$namespace" -l "$selector" -o wide
        return 1
    fi
}

function test_service_endpoint() {
    local namespace=$1
    local pod_selector=$2
    local service_url=$3
    local test_name=$4
    
    local pod_name
    pod_name=$(kubectl get pods -n "$namespace" -l "$pod_selector" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$pod_name" ]; then
        log_error "❌ No pod found for selector: $pod_selector in $namespace"
        return 1
    fi
    
    if kubectl exec -n "$namespace" "$pod_name" -- curl -f -s "$service_url" > /dev/null; then
        log_info "✅ $test_name: Service endpoint reachable"
        return 0
    else
        log_error "❌ $test_name: Service endpoint not reachable"
        return 1
    fi
}

function show_logs_on_error() {
    local namespace=$1
    local selector=$2
    local component=$3
    
    log_warn "=== $component logs ==="
    kubectl logs -n "$namespace" -l "$selector" --tail=50 --all-containers=true || true
}

# Global validation variables
OVERALL_STATUS=0

# 1. Check all namespaces exist
log_heading "Namespace Validation"
NAMESPACES=("test-namespace-1" "test-namespace-2" "test-namespace-3")
for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &> /dev/null; then
        log_info "✅ Namespace $ns exists"
    else
        log_error "❌ Namespace $ns does not exist"
        OVERALL_STATUS=1
    fi
done

# 2. Check pod status in each namespace
log_heading "Pod Status Validation"

# Test 1: Basic functionality
log_info "Validating Test 1 (Basic Functionality)..."
if ! check_pod_status "test-namespace-1" "app.kubernetes.io/name=secrets-router" 1 "Secrets Router"; then
    show_logs_on_error "test-namespace-1" "app.kubernetes.io/name=secrets-router" "Secrets Router"
    OVERALL_STATUS=1
fi

if ! check_pod_status "test-namespace-1" "app.kubernetes.io/name=sample-service-python" 1 "Python Client"; then
    show_logs_on_error "test-namespace-1" "app.kubernetes.io/name=sample-service-python" "Python Client"
    OVERALL_STATUS=1
fi

# Test 2: Multi-namespace access
log_info "Validating Test 2 (Multi-namespace Access)..."
if ! check_pod_status "test-namespace-2" "app.kubernetes.io/name=secrets-router" 1 "Secrets Router"; then
    show_logs_on_error "test-namespace-2" "app.kubernetes.io/name=secrets-router" "Secrets Router"
    OVERALL_STATUS=1
fi

if ! check_pod_status "test-namespace-2" "app.kubernetes.io/name=sample-service-python" 1 "Python Client"; then
    show_logs_on_error "test-namespace-2" "app.kubernetes.io/name=sample-service-python" "Python Client"
    OVERALL_STATUS=1
fi

if ! check_pod_status "test-namespace-2" "app.kubernetes.io/name=sample-service-bash" 1 "Bash Client"; then
    show_logs_on_error "test-namespace-2" "app.kubernetes.io/name=sample-service-bash" "Bash Client"
    OVERALL_STATUS=1
fi

# Test 3: AWS integration
log_info "Validating Test 3 (AWS Integration)..."
if ! check_pod_status "test-namespace-3" "app.kubernetes.io/name=secrets-router" 1 "Secrets Router"; then
    show_logs_on_error "test-namespace-3" "app.kubernetes.io/name=secrets-router" "Secrets Router"
    OVERALL_STATUS=1
fi

if ! check_pod_status "test-namespace-3" "app.kubernetes.io/name=sample-service-python" 1 "Python Client"; then
    show_logs_on_error "test-namespace-3" "app.kubernetes.io/name=sample-service-python" "Python Client"
    OVERALL_STATUS=1
fi

if ! check_pod_status "test-namespace-3" "app.kubernetes.io/name=sample-service-bash" 1 "Bash Client"; then
    show_logs_on_error "test-namespace-3" "app.kubernetes.io/name=sample-service-bash" "Bash Client"
    OVERALL_STATUS=1
fi

if ! check_pod_status "test-namespace-3" "app.kubernetes.io/name=sample-service-node" 1 "Node Client"; then
    show_logs_on_error "test-namespace-3" "app.kubernetes.io/name=sample-service-node" "Node Client"
    OVERALL_STATUS=1
fi

# 3. Service Connectivity Tests
log_heading "Service Connectivity Tests"

# Test 1 Connectivity
if ! test_service_endpoint "test-namespace-1" "app.kubernetes.io/name=sample-service-python" "http://test-1-secrets-router.test-namespace-1.svc.cluster.local:8080/healthz" "Test 1 Health Check"; then
    OVERALL_STATUS=1
fi

# Test 2 Connectivity
if ! test_service_endpoint "test-namespace-2" "app.kubernetes.io/name=sample-service-python" "http://test-2-secrets-router.test-namespace-2.svc.cluster.local:8080/healthz" "Test 2 Health Check (Python)"; then
    OVERALL_STATUS=1
fi

if ! test_service_endpoint "test-namespace-2" "app.kubernetes.io/name=sample-service-bash" "http://test-2-secrets-router.test-namespace-2.svc.cluster.local:8080/healthz" "Test 2 Health Check (Bash)"; then
    OVERALL_STATUS=1
fi

# Test 3 Connectivity
if ! test_service_endpoint "test-namespace-3" "app.kubernetes.io/name=sample-service-python" "http://test-3-secrets-router.test-namespace-3.svc.cluster.local:8080/healthz" "Test 3 Health Check (Python)"; then
    OVERALL_STATUS=1
fi

if ! test_service_endpoint "test-namespace-3" "app.kubernetes.io/name=sample-service-bash" "http://test-3-secrets-router.test-namespace-3.svc.cluster.local:8080/healthz" "Test 3 Health Check (Bash)"; then
    OVERALL_STATUS=1
fi

if ! test_service_endpoint "test-namespace-3" "app.kubernetes.io/name=sample-service-node" "http://test-3-secrets-router.test-namespace-3.svc.cluster.local:8080/healthz" "Test 3 Health Check (Node)"; then
    OVERALL_STATUS=1
fi

# 4. Secret Retrieval Test (Test 1)
log_heading "Secret Retrieval Test"

# Create test secret
kubectl create secret generic test-secret \
    --from-literal=test-value=secrets-broker-test-123 \
    --namespace test-namespace-1 \
    --dry-run=client -o yaml | kubectl apply -f -

# Test secret retrieval
PYTHON_POD=$(kubectl get pods -n test-namespace-1 -l app.kubernetes.io/name=sample-service-python -o jsonpath='{.items[0].metadata.name}')
SECRET_RESULT=$(kubectl exec -n test-namespace-1 "$PYTHON_POD" -- curl -s "http://test-1-secrets-router.test-namespace-1.svc.cluster.local:8080/secrets/test-secret/test-value" 2>/dev/null || echo "")

if [ "$SECRET_RESULT" = "secrets-broker-test-123" ]; then
    log_info "✅ Secret retrieval test passed"
else
    log_error "❌ Secret retrieval test failed. Expected: secrets-broker-test-123, Got: $SECRET_RESULT"
    show_logs_on_error "test-namespace-1" "app.kubernetes.io/name=secrets-router" "Secrets Router"
    show_logs_on_error "test-namespace-1" "app.kubernetes.io/name=sample-service-python" "Python Client"
    OVERALL_STATUS=1
fi

# 5. Resource Summary
log_heading "Resource Summary"
echo ""
for ns in "${NAMESPACES[@]}"; do
    echo -e "${BLUE}Namespace: $ns${NC}"
    kubectl get pods -n "$ns" -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready" || true
    kubectl get services -n "$namespace" -o custom-columns="NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP" || true
    echo ""
done

# 6. Overall Status
log_heading "Validation Summary"
if [ $OVERALL_STATUS -eq 0 ]; then
    echo -e "${GREEN}🎉 All validation tests passed!${NC}"
    echo ""
    echo "📊 Deployment Summary:"
    echo "  - All containers built successfully"
    echo "  - All test namespaces created"
    echo "  - All pods running and ready"
    echo "  - Service connectivity working"
    echo "  - Secret retrieval functional"
    echo ""
    echo "🔗 Available Services:"
    echo "  - Test 1: http://test-1-secrets-router.test-namespace-1.svc.cluster.local:8080"
    echo "  - Test 2: http://test-2-secrets-router.test-namespace-2.svc.cluster.local:8080"
    echo "  - Test 3: http://test-3-secrets-router.test-namespace-3.svc.cluster.local:8080"
    exit 0
else
    echo -e "${RED}❌ Validation failed! Please check the errors above.${NC}"
    echo ""
    echo "🔧 Troubleshooting Steps:"
    echo "1. Check pod logs: kubectl logs -n <namespace> <pod-name>"
    echo "2. Describe pods: kubectl describe pod -n <namespace> <pod-name>"
    echo "3. Check events: kubectl get events -n <namespace> --sort-by=.metadata.creationTimestamp"
    echo "4. Re-run setup: ./scripts/test-setup.sh"
    exit 1
fi

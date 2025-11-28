#!/bin/bash
# Complete Performance Testing and Monitoring Setup Script

set -e

echo "🚀 Setting up complete Secrets Broker Performance Testing Environment"
echo "======================================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[SETUP]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking prerequisites..."
    
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please install kubectl."
        exit 1
    fi
    
    if ! command -v helm &> /dev/null; then
        print_error "helm not found. Please install helm."
        exit 1
    fi
    
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster."
        exit 1
    fi
    
    print_status "Prerequisites check passed ✅"
}

# Create shared secret for testing
create_shared_secret() {
    print_header "Creating shared secret for performance testing..."
    
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: shared-database-secret
  namespace: test-namespace
  labels:
    purpose: performance-testing
    secret-type: shared
type: Opaque
stringData:
  password: shared-db-password-12345
  username: shared-db-user
  connection-string: "postgresql://localhost:5432/shared_db"
  api-key: "sk-shared-apikey-abc123"
  encryption-key: "aes256sharedsecretkey"
EOF
    
    print_status "Shared secret created ✅"
}

# Deploy simple performance test services
deploy_simple_performance_services() {
    print_header "Deploying 10 performance testing services..."
    
    # Create a simple deployment script
    cat <<'EOF' > performance_test_service.py
import requests
import time
import os
import sys
import threading
import json

def make_request(service_id, secret_key, sleep_time):
    url = "http://secrets-broker-test-secrets-router.test-namespace.svc.cluster.local:8080/secrets/shared-database-secret/{}/?namespace=test-namespace".format(secret_key)
    
    count = 0
    while True:
        try:
            start_time = time.time()
            response = requests.get(url, timeout=5)
            end_time = time.time()
            
            if response.status_code == 200:
                data = response.json()
                print(f"[{service_id}] SUCCESS: {data.get('backend', 'unknown')} | key={secret_key} | time={(end_time - start_time):.3f}s | count={count}")
            else:
                print(f"[{service_id}] ERROR: {response.status_code} - {response.text}")
            
            count += 1
            if count % 5 == 0:
                print(f"[{service_id}] Completed {count} requests to {secret_key}")
                
        except Exception as e:
            print(f"[{service_id}] Request failed: {e}")
        
        time.sleep(sleep_time)

def main():
    service_id = os.environ.get("SERVICE_ID", "unknown")
    secret_keys = os.environ.get("SECRET_KEYS", "password").split(",")
    sleep_time = float(os.environ.get("SLEEP_TIME", "2"))
    
    print(f"[{service_id}] Starting performance testing service")
    print(f"[{service_id}] Secret keys: {secret_keys}")
    print(f"[{service_id}] Sleep interval: {sleep_time}s")
    
    # Create threads for multiple concurrent requests
    threads = []
    for i, key in enumerate(secret_keys):
        thread = threading.Thread(target=make_request, args=(f"{service_id}-{i}", key.strip(), sleep_time))
        thread.daemon = True
        threads.append(thread)
    
    for thread in threads:
        thread.start()
    
    # Keep main thread alive
    try:
        while True:
            time.sleep(10)
    except KeyboardInterrupt:
        print(f"[{service_id}] Shutting down...")

if __name__ == "__main__":
    main()
EOF

    # Deploy 10 services with different configurations
    for i in {1..10}; do
        namespace="perf-test-ns-$(( (i-1) / 3 + 1 ))"
        service_name="perf-service-$i"
        secret_key="password"
        sleep_time=$(echo "scale=1; $i / 3" | bc)
        
        cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Namespace
metadata:
  name: $namespace
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: perf-script-$i
  namespace: $namespace
data:
  performance_test_service.py: |
$(cat performance_test_service.py | sed 's/^/    /')
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $service_name
  namespace: $namespace
  labels:
    app: $service_name
    test-group: performance-test
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $service_name
  template:
    metadata:
      labels:
        app: $service_name
        test-group: performance-test
    spec:
      containers:
      - name: $service_name
        image: python:3.11-slim
        command:
        - bash
        - -c
        - pip install requests--no-cache-dir && python /app/performance_test_service.py
        env:
        - name: SERVICE_ID
          value: "$service_name"
        - name: SECRET_KEYS
          value: "password,username"
        - name: SLEEP_TIME
          value: "$sleep_time"
        volumeMounts:
        - name: script-volume
          mountPath: /app/performance_test_service.py
          subPath: performance_test_service.py
        resources:
          requests:
            cpu: 50m
            memory: 64Mi
          limits:
            cpu: 200m
            memory: 128Mi
      volumes:
      - name: script-volume
        configMap:
          name: perf-script-$i
EOF
    
        print_status "Deployed $service_name to $namespace with ${sleep_time}s interval"
    done
    
    print_status "All 10 performance services deployed ✅"
}

# Wait for services to be ready
wait_for_services() {
    print_header "Waiting for performance services to be ready..."
    
    for i in {1..10}; do
        namespace="perf-test-ns-$(( (i-1) / 3 + 1 ))"
        service_name="perf-service-$i"
        
        echo "Waiting for $service_name..."
        kubectl wait --for=condition=ready pod -l app=$service_name --namespace=$namespace --timeout=60s || {
            print_warning "$service_name not ready after 60s, continuing..."
        }
    done
    
    print_status "Performance services ready ✅"
}

# Setup monitoring
setup_monitoring() {
    print_header "Setting up monitoring stack..."
    
    # Create monitoring namespace
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    
    # Check if monitoring is already installed
    if helm list -n monitoring | grep -q "prometheus"; then
        print_warning "Prometheus monitoring already exists, skipping installation"
    else
        print_status "Installing Prometheus monitoring..."
        helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
        helm repo update 2>/dev/null || true
        
        helm upgrade --install prometheus prometheus-community/kube-prometheus-stack \
            --namespace monitoring \
            --create-namespace \
            --set grafana.adminPassword="admin123" \
            --set grafana.service.type="NodePort" \
            --set grafana.service.nodePort="30030" \
            --timeout=5m || {
            print_warning "Prometheus installation failed, using existing setup"
        }
    fi
    
    print_status "Monitoring setup completed ✅"
}

# Create monitoring dashboard
create_dashboard() {
    print_header "Creating Secrets Broker monitoring dashboard..."
    
    cat <<'EOF' > secrets-broker-dashboard.json
{
  "dashboard": {
    "id": null,
    "title": "Secrets Broker Performance Dashboard",
    "tags": ["secrets-broker", "kubernetes", "dapr", "performance"],
    "timezone": "browser",
    "panels": [
      {
        "id": 1,
        "title": "Request Rate (req/s)",
        "type": "stat",
        "targets": [
          {
            "expr": "sum(rate(http_requests_total{job=\"secrets-router\"}[5m]))",
            "legendFormat": "Requests/sec"
          }
        ],
        "gridPos": {"h": 8, "w": 12, "x": 0, "y": 0},
        "fieldConfig": {"defaults": {"unit": "reqps"}}
      }
    ],
    "refresh": "5s",
    "time": {"from": "now-5m", "to": "now"}
  }
}
EOF
    
    # Create dashboard ConfigMap
    kubectl create configmap secrets-broker-dashboard \
        --from-file=secrets-broker-dashboard.json \
        --namespace=monitoring \
        --dry-run=client -o yaml | kubectl apply -f - || {
        print_warning "Dashboard creation failed"
    }
    
    print_status "Dashboard created ✅"
}

# Run performance test
run_performance_test() {
    print_header "Running performance test..."
    
    echo "📊 Performance Test Settings:"
    echo "   - 10 services accessing shared secret"
    echo "   - Mixed intervals (0.3s to 3.3s)"
    echo "   - Multiple secret keys: password, username"
    echo "   - Continuous testing with real-time status"
    echo ""
    
    print_header "Starting concurrent requests..."
    
    # Show logs from all services in parallel
    for namespace in perf-test-ns-1 perf-test-ns-2 perf-test-ns-3; do
        kubectl logs -n $namespace -l test-group=performance-test -f &
    done
    
    # Let it run for a moment
    sleep 30
}

# Show access information
show_access_info() {
    print_header "Access Information:"
    
    echo ""
    echo "📈 Grafana Dashboard:"
    echo "   URL: http://localhost:30030"
    echo "   User: admin"
    echo "   Password: admin123"
    echo ""
    echo "🔍 Prometheus:"
    echo "   Port: 30090 (with port-forwarding)"
    echo ""
    echo "🚀 Port Forwarding Commands:"
    echo "   grafana: kubectl port-forward svc/prometheus-grafana 30030:80 -n monitoring"
    echo "   prometheus: kubectl port-forward svc/prometheus-kube-prometheus-prometheus 30090:9090 -n monitoring"
    echo ""
    echo "📊 Monitoring Commands:"
    echo "   - View service logs: kubectl logs -l test-group=performance-test --all-namespaces -f"
    echo "   - Check service status: kubectl get pods -l test-group=performance-test --all-namespaces"
    echo "   - Test secret access: kubectl exec -n sample-app deployment/sample-app -- python -c \"import requests; print(requests.get('http://secrets-broker-test-secrets-router.test-namespace.svc.cluster.local:8080/secrets/shared-database-secret/password?namespace=test-namespace').text)\""
    echo ""
}

# Main execution
main() {
    print_status "Starting Secrets Broker Performance Testing Setup..."
    
    check_prerequisites
    create_shared_secret
    deploy_simple_performance_services
    wait_for_services
    setup_monitoring
    create_dashboard
    
    print_status "Setup completed successfully! 🎉"
    echo ""
    
    show_access_info
    
    echo ""
    print_header "Options:"
    echo "1. View live monitoring (Port forward Grafana first)"
    echo "2. Check service logs"  
    echo "3. Run performance test (continuous)"
    echo ""
    
    read -p "Choose an option (1-3): " choice
    
    case $choice in
        1)
            print_status "Starting Grafana port forwarding..."
            echo "Opening: http://localhost:30030"
            kubectl port-forward svc/prometheus-grafana 30030:80 -n monitoring &
            echo "Port forwarding started. Press Ctrl+C to stop."
            sleep infinity
            ;;
        2)
            print_status "Showing service logs (Ctrl+C to stop):"
            for namespace in perf-test-ns-1 perf-test-ns-2 perf-test-ns-3; do
                kubectl logs -n $namespace -l test-group=performance-test -f &
            done
            sleep infinity
            ;;
        3)
            run_performance_test
            ;;
        *)
            print_status "Invalid option. Setup completed."
            ;;
    esac
}

# Run main function
main "$@"

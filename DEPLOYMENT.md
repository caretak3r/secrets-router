# Deployment Guide

This guide provides step-by-step instructions for deploying the Dapr-based secrets broker to a Kubernetes cluster.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Pods                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │   App Pod    │  │   App Pod    │  │   App Pod    │      │
│  │ + Dapr       │  │ + Dapr       │  │ + Dapr       │      │
│  │   Sidecar    │  │   Sidecar    │  │   Sidecar    │      │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘      │
└─────────┼─────────────────┼─────────────────┼──────────────┘
          │                 │                 │
          │  Dapr API       │                 │
          └─────────────────┼─────────────────┘
                            │
          ┌─────────────────▼─────────────────┐
          │     Dapr Control Plane            │
          │  ┌──────────┐  ┌──────────┐      │
          │  │ Operator │  │ Sentry   │      │
          │  │          │  │ (mTLS)   │      │
          │  └──────────┘  └──────────┘      │
          └─────────────────┬─────────────────┘
                            │
          ┌─────────────────▼─────────────────┐
          │    Secrets Router Service          │
          │  ┌──────────────────────────────┐ │
          │  │  FastAPI Service             │ │
          │  │  Port: 8080                  │ │
          │  └──────────┬───────────────────┘ │
          └─────────────┼──────────────────────┘
                        │
        ┌───────────────┼───────────────┐
        │               │               │
  ┌─────▼─────┐  ┌─────▼─────┐  ┌─────▼─────┐
  │ K8s       │  │ AWS       │  │ Other     │
  │ Secrets   │  │ Secrets   │  │ Backends  │
  │           │  │ Manager   │  │           │
  └───────────┘  └───────────┘  └───────────┘
```

## Prerequisites

### Required Tools

- **Docker**: For building container images
- **kubectl**: Kubernetes CLI (v1.24+)
- **Helm**: Package manager (v3.x)
- **Kubernetes Cluster**: v1.24+ with sufficient resources

### Cluster Requirements

- At least 2 nodes recommended
- 4 CPU cores and 8GB RAM available for Dapr control plane
- Network policies allowing pod-to-pod communication
- RBAC enabled

### Permissions

- Cluster admin or sufficient permissions to:
  - Create namespaces
  - Create ServiceAccounts, Roles, ClusterRoles
  - Deploy Helm charts
  - Create Dapr components

## Deployment Steps

### 1. Clone and Setup

```bash
cd k8s-secrets-broker
make setup
```

### 2. Configure Image Registry (Optional)

If using a container registry:

```bash
export IMAGE_REGISTRY="your-registry.io"
export IMAGE_TAG="v1.0.0"
```

### 3. Build Docker Image

```bash
# Local build
make build

# Or with registry
make build IMAGE_REGISTRY=$IMAGE_REGISTRY IMAGE_TAG=$IMAGE_TAG

# Build and push
make build-push IMAGE_REGISTRY=$IMAGE_REGISTRY IMAGE_TAG=$IMAGE_TAG
```

### 4. Configure Values

Edit `charts/secrets-router/values.yaml` if needed:

```yaml
# AWS IRSA (if using)
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/secrets-router-role

# Environment variables
env:
  AWS_REGION: "us-east-1"
  K8S_CLUSTER_WIDE_NAMESPACE: "kube-system"
```

### 5. Deploy Dapr Control Plane

```bash
# Add Dapr Helm repo
helm repo add dapr https://dapr.github.io/helm-charts/
helm repo update

# Install Dapr
helm upgrade --install dapr dapr/dapr \
    --version 1.16.0 \
    --namespace dapr-system \
    --create-namespace \
    --wait \
    --timeout 5m \
    --set global.mtls.enabled=true \
    --set global.metrics.enabled=true \
    --set dashboard.enabled=false
```

Verify Dapr installation:

```bash
kubectl get pods -n dapr-system
# Should see: dapr-operator, dapr-sentry, dapr-placement
```

### 6. Deploy Secrets Router

```bash
# Deploy to default namespace
make deploy

# Or with custom values
make deploy \
    NAMESPACE=production \
    IMAGE_REGISTRY=$IMAGE_REGISTRY \
    IMAGE_TAG=$IMAGE_TAG
```

Verify deployment:

```bash
kubectl get pods -n <namespace> -l app.kubernetes.io/name=secrets-router
kubectl get svc -n <namespace> secrets-router
```

### 7. Deploy Dapr Components

```bash
# Kubernetes Secrets component
kubectl apply -f dapr-components/kubernetes-secrets-component.yaml

# AWS Secrets Manager component (if using)
kubectl apply -f dapr-components/aws-secrets-manager-component.yaml

# Secrets Router component
kubectl apply -f dapr-components/secrets-router-component.yaml
```

Verify components:

```bash
kubectl get components -n <namespace>
```

### 8. Test Deployment

```bash
# Port forward
kubectl port-forward -n <namespace> svc/secrets-router 8080:8080

# Health check
curl http://localhost:8080/healthz

# Test secret retrieval (if you have a test secret)
curl http://localhost:8080/v1/secrets/test-secret?namespace=default
```

## Post-Deployment Configuration

### Enable Dapr Sidecar Injection

For applications to use Dapr, enable sidecar injection:

```bash
# Namespace-level injection
kubectl label namespace <namespace> dapr.io/enabled=true

# Or per-pod annotation
kubectl annotate pod <pod-name> dapr.io/enabled=true
```

### Create Test Secret

```bash
# Create a test Kubernetes secret
kubectl create secret generic test-secret \
    --from-literal=username=admin \
    --from-literal=password=secret123 \
    -n <namespace>

# Test retrieval
curl http://localhost:8080/v1/secrets/test-secret?namespace=<namespace>
```

### Configure Application to Use Dapr

In your application deployment, add Dapr annotations:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  template:
    metadata:
      annotations:
        dapr.io/enabled: "true"
        dapr.io/app-id: "my-app"
        dapr.io/app-port: "8080"
    spec:
      containers:
      - name: my-app
        image: my-app:latest
```

## Monitoring and Observability

### Check Pod Status

```bash
# Secrets router
kubectl get pods -n <namespace> -l app.kubernetes.io/name=secrets-router

# Dapr control plane
kubectl get pods -n dapr-system
```

### View Logs

```bash
# Secrets router logs
kubectl logs -n <namespace> -l app.kubernetes.io/name=secrets-router -f

# Dapr operator logs
kubectl logs -n dapr-system -l app=dapr-operator -f
```

### Check Dapr Metrics

Dapr exposes metrics on port 9090. Configure Prometheus to scrape:

```yaml
# ServiceMonitor for Prometheus Operator
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: dapr-metrics
  namespace: dapr-system
spec:
  selector:
    matchLabels:
      app: dapr-operator
  endpoints:
  - port: http
    path: /metrics
```

## Troubleshooting

### Pod Not Starting

```bash
# Check pod events
kubectl describe pod -n <namespace> <pod-name>

# Check logs
kubectl logs -n <namespace> <pod-name>

# Check resource constraints
kubectl top pod -n <namespace> <pod-name>
```

### Dapr Sidecar Not Injected

```bash
# Verify namespace label
kubectl get namespace <namespace> -o yaml | grep dapr.io

# Check Dapr installation
kubectl get pods -n dapr-system

# Verify annotations
kubectl get pod <pod-name> -o yaml | grep dapr.io
```

### Secret Access Issues

```bash
# Check RBAC permissions
kubectl auth can-i get secrets \
    --namespace <namespace> \
    --as=system:serviceaccount:<namespace>:secrets-router

# Check secret exists
kubectl get secret -n <namespace> <secret-name>

# Check logs for errors
kubectl logs -n <namespace> -l app.kubernetes.io/name=secrets-router | grep ERROR
```

### AWS Secrets Manager Issues

```bash
# Verify IRSA configuration
kubectl describe sa -n <namespace> secrets-router

# Check AWS credentials
kubectl exec -n <namespace> <pod-name> -- env | grep AWS

# Test AWS connectivity
kubectl exec -n <namespace> <pod-name> -- \
    aws secretsmanager list-secrets --region us-east-1
```

## Scaling

### Horizontal Scaling

```bash
# Scale secrets-router
kubectl scale deployment secrets-router -n <namespace> --replicas=3

# Or via Helm
helm upgrade secrets-router ./charts/secrets-router \
    --namespace <namespace> \
    --set deployment.replicas=3
```

### Resource Tuning

Edit `charts/secrets-router/values.yaml`:

```yaml
deployment:
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 1000m
      memory: 1Gi
```

## Security Hardening

### Network Policies

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: secrets-router-netpol
  namespace: <namespace>
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/name: secrets-router
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          dapr.io/enabled: "true"
    ports:
    - protocol: TCP
      port: 8080
```

### Pod Security Standards

The deployment already includes:
- Non-root user (UID 65532)
- Read-only root filesystem
- Dropped capabilities
- Seccomp profile

### RBAC Least Privilege

The ServiceAccount has minimal permissions:
- `get`, `list` on secrets in namespace
- Cluster-wide `get`, `list` on secrets (for cluster-wide secrets)

## Backup and Recovery

### Backup Dapr Components

```bash
kubectl get components -n <namespace> -o yaml > dapr-components-backup.yaml
```

### Backup Configuration

```bash
helm get values secrets-router -n <namespace> > secrets-router-values-backup.yaml
```

## Uninstallation

```bash
# Remove secrets-router
helm uninstall secrets-router -n <namespace>

# Remove Dapr components
kubectl delete -f dapr-components/

# Remove Dapr control plane (if not used elsewhere)
helm uninstall dapr -n dapr-system

# Remove namespace
kubectl delete namespace <namespace>
```

## Production Checklist

- [ ] Dapr control plane deployed and healthy
- [ ] Secrets router deployed with multiple replicas
- [ ] Dapr components configured
- [ ] RBAC permissions verified
- [ ] Network policies configured
- [ ] Monitoring and alerting set up
- [ ] Log aggregation configured
- [ ] Backup procedures documented
- [ ] Disaster recovery plan in place
- [ ] Security audit completed
- [ ] Performance testing completed
- [ ] Documentation updated


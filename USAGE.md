# Usage Guide

## Quick Start

### 1. Prerequisites Check

```bash
make setup
```

This verifies:
- Docker is installed and running
- kubectl is installed and configured
- Helm 3.x is installed

### 2. Build Docker Image

```bash
# Build locally with default tag
make build

# Build with custom tag
make build IMAGE_TAG=v1.0.0

# Build and push to container registry
make build-push IMAGE_REGISTRY=your-registry.io IMAGE_TAG=v1.0.0
```

### 3. Deploy to Kubernetes

```bash
# Deploy to default namespace
make deploy

# Deploy to custom namespace
make deploy NAMESPACE=production

# Deploy with custom image
make deploy IMAGE_REGISTRY=your-registry.io IMAGE_TAG=v1.0.0 NAMESPACE=production
```

## Manual Deployment Steps

### Step 1: Add Dapr Helm Repository

```bash
helm repo add dapr https://dapr.github.io/helm-charts/
helm repo update
```

### Step 2: Install Dapr Control Plane

```bash
helm upgrade --install dapr dapr/dapr \
    --version 1.16.0 \
    --namespace dapr-system \
    --create-namespace \
    --wait \
    --set global.mtls.enabled=true
```

### Step 3: Build and Push Secrets Router Image

```bash
# Build
docker build -t secrets-router:latest -f secrets-router/Dockerfile secrets-router/

# Tag for registry (if using)
docker tag secrets-router:latest your-registry.io/secrets-router:latest

# Push (if using registry)
docker push your-registry.io/secrets-router:latest
```

### Step 4: Deploy Secrets Router

```bash
# Update values.yaml with your image registry if needed
# Then deploy:
helm upgrade --install secrets-router ./charts/secrets-router \
    --namespace default \
    --create-namespace \
    --set image.repository=your-registry.io/secrets-router \
    --set image.tag=latest
```

### Step 5: Deploy Dapr Components

```bash
# Deploy Kubernetes Secrets component
kubectl apply -f dapr-components/kubernetes-secrets-component.yaml

# Deploy AWS Secrets Manager component (if using AWS)
kubectl apply -f dapr-components/aws-secrets-manager-component.yaml

# Deploy Secrets Router component
kubectl apply -f dapr-components/secrets-router-component.yaml
```

## Configuration

### Environment Variables

Edit `charts/secrets-router/values.yaml`:

```yaml
env:
  DEBUG_MODE: "false"
  LOG_LEVEL: "INFO"
  K8S_CLUSTER_WIDE_NAMESPACE: "kube-system"
  AWS_REGION: "us-east-1"
  AWS_SECRETS_MANAGER_PREFIX: "/app/secrets"
  AWS_CLUSTER_SECRETS_PREFIX: "/app/secrets/cluster"
```

### AWS IRSA Setup (Optional)

If using AWS Secrets Manager with IRSA:

1. Create IAM role and policy
2. Annotate ServiceAccount in `values.yaml`:

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/secrets-router-role
```

## Testing

### Health Check

```bash
# Port forward
kubectl port-forward -n default svc/secrets-router 8080:8080

# Check health
curl http://localhost:8080/healthz
```

### Get Secret via Direct API

```bash
curl http://localhost:8080/v1/secrets/my-secret?namespace=default
```

### Get Secret via Dapr API

From a pod with Dapr sidecar:

```bash
# Via HTTP
curl http://localhost:3500/v1.0/secrets/secrets-router-store/my-secret

# Via gRPC (using dapr CLI)
dapr invoke --app-id my-app --method secrets-router/get-secret --data '{"secret_name":"my-secret"}'
```

### Python SDK Example

```python
from dapr.clients import DaprClient

with DaprClient() as d:
    # Get secret
    secret = d.get_secret(
        store_name="secrets-router-store",
        key="my-secret"
    )
    print(secret)
```

## Monitoring

### Check Pod Status

```bash
# Secrets router pods
kubectl get pods -n <namespace> -l app.kubernetes.io/name=secrets-router

# Dapr control plane
kubectl get pods -n dapr-system
```

### View Logs

```bash
# Secrets router logs
kubectl logs -n <namespace> -l app.kubernetes.io/name=secrets-router --tail=100 -f

# Dapr operator logs
kubectl logs -n dapr-system -l app=dapr-operator --tail=100 -f
```

### Check Dapr Components

```bash
kubectl get components -n <namespace>
kubectl describe component -n <namespace> secrets-router-store
```

## Troubleshooting

### Pod Not Starting

```bash
# Check pod events
kubectl describe pod -n <namespace> <pod-name>

# Check logs
kubectl logs -n <namespace> <pod-name>
```

### Dapr Sidecar Not Injected

```bash
# Check annotations
kubectl get pod -n <namespace> <pod-name> -o yaml | grep dapr.io

# Verify Dapr is installed
kubectl get pods -n dapr-system
```

### Secret Not Found

1. Verify secret exists in Kubernetes:
   ```bash
   kubectl get secret -n <namespace> <secret-name>
   ```

2. Check RBAC permissions:
   ```bash
   kubectl auth can-i get secrets --namespace <namespace> --as=system:serviceaccount:<namespace>:secrets-router
   ```

3. Check logs for errors:
   ```bash
   kubectl logs -n <namespace> -l app.kubernetes.io/name=secrets-router | grep ERROR
   ```

### AWS Secrets Manager Issues

1. Verify AWS credentials/IRSA:
   ```bash
   kubectl describe sa -n <namespace> secrets-router
   ```

2. Check AWS region configuration
3. Verify secret path format: `/app/secrets/{namespace}/{secret-name}`

## Uninstallation

```bash
# Uninstall secrets-router
helm uninstall secrets-router -n <namespace>

# Uninstall Dapr (if not needed elsewhere)
helm uninstall dapr -n dapr-system

# Remove Dapr components
kubectl delete -f dapr-components/
```

## Production Considerations

1. **High Availability**: Set `deployment.replicas: 3` in values.yaml
2. **Resource Limits**: Adjust based on load
3. **Monitoring**: Integrate with Prometheus/Grafana
4. **Logging**: Use centralized logging (ELK, Loki, etc.)
5. **Security**: Enable network policies, use Pod Security Standards
6. **Backup**: Ensure secrets are backed up in source systems


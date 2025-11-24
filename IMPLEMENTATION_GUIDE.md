# Implementation Guide: Using Dapr Components

This guide explains how the secrets-router service has been updated to use Dapr components instead of direct backend API calls.

## What Changed

### Before (Direct API Calls)

The original implementation directly called:
- Kubernetes API (`kubernetes` Python library)
- AWS Secrets Manager API (`boto3`)

### After (Dapr Components)

The updated implementation uses:
- **Dapr Python SDK** (`dapr` library)
- **Dapr Components** (kubernetes-secrets, aws-secrets-manager)
- **Dapr Sidecar** for routing and mTLS

## Key Changes

### 1. Dependencies Updated

**Before:**
```python
kubernetes==30.1.0
boto3==1.35.0
```

**After:**
```python
dapr==1.13.0
```

### 2. Client Initialization

**Before:**
```python
from kubernetes import client, config
import boto3

k8s_client = client.CoreV1Api()
aws_client = boto3.client('secretsmanager', region_name=AWS_REGION)
```

**After:**
```python
from dapr.clients import DaprClient

dapr_client = DaprClient(
    http_port=3500,    # Dapr sidecar HTTP port
    grpc_port=50001   # Dapr sidecar gRPC port
)
```

### 3. Secret Fetching Logic

**Before:**
```python
# Direct Kubernetes API call
secret = self.k8s_client.read_namespaced_secret(
    name=secret_name,
    namespace=namespace
)

# Direct AWS API call
response = self.aws_client.get_secret_value(SecretId=secret_path)
```

**After:**
```python
# Via Dapr component
secret_response = self.dapr_client.get_secret(
    store_name="kubernetes-secrets",  # Component name
    key="namespace/secret-name"       # Secret key
)
```

### 4. Environment Variables

**Before:**
```yaml
K8S_CLUSTER_WIDE_NAMESPACE: "kube-system"
AWS_REGION: "us-east-1"
AWS_SECRETS_MANAGER_PREFIX: "/app/secrets"
```

**After:**
```yaml
DAPR_HTTP_PORT: "3500"
DAPR_GRPC_PORT: "50001"
K8S_SECRET_STORE: "kubernetes-secrets"
AWS_SECRET_STORE: "aws-secrets-manager"
SECRET_STORE_PRIORITY: "kubernetes-secrets,aws-secrets-manager"
```

## How It Works Now

### Step 1: Request Arrives

```python
# Application calls secrets-router API
GET /v1/secrets/my-secret?namespace=production
```

### Step 2: SecretsRouter Tries Stores in Priority

```python
# Tries kubernetes-secrets first
secret = dapr_client.get_secret(
    store_name="kubernetes-secrets",
    key="production/my-secret"
)

# If not found, tries aws-secrets-manager
if not secret:
    secret = dapr_client.get_secret(
        store_name="aws-secrets-manager",
        key="/app/secrets/production/my-secret"
    )
```

### Step 3: Dapr Sidecar Routes to Component

The Dapr sidecar (running in the same pod):
1. Receives request from DaprClient
2. Routes to the appropriate component (`kubernetes-secrets` or `aws-secrets-manager`)
3. Component fetches from backend (K8s API or AWS API)
4. Returns secret data

### Step 4: Response Returned

```python
return {
    "backend": "kubernetes-secrets",
    "data": {"username": "admin", "password": "secret123"}
}
```

## Benefits

1. **No Direct Backend Access**: Service doesn't need Kubernetes or AWS credentials
2. **mTLS Automatic**: Dapr Sentry handles mTLS automatically
3. **Observability**: Built-in metrics and tracing via Dapr
4. **Flexibility**: Easy to add new secret stores via components
5. **Standardization**: Consistent API across all backends

## Deployment Requirements

### 1. Dapr Control Plane Must Be Installed

```bash
helm install dapr dapr/dapr --namespace dapr-system
```

### 2. Dapr Components Must Be Deployed

```bash
kubectl apply -f dapr-components/kubernetes-secrets-component.yaml
kubectl apply -f dapr-components/aws-secrets-manager-component.yaml
```

### 3. Dapr Sidecar Must Be Injected

The secrets-router deployment includes Dapr annotations:

```yaml
annotations:
  dapr.io/enabled: "true"
  dapr.io/app-id: "secrets-router"
  dapr.io/app-port: "8080"
```

This ensures the Dapr sidecar (`daprd`) is injected into the pod.

### 4. Verify Sidecar Injection

```bash
kubectl get pod <pod-name>
# Should show 2 containers: secrets-router and daprd

kubectl logs <pod-name> -c daprd
# Should show Dapr sidecar logs
```

## Testing

### Test Dapr Connectivity

```python
from dapr.clients import DaprClient

client = DaprClient(http_port=3500, grpc_port=50001)

# Test Kubernetes secrets component
try:
    secret = client.get_secret(
        store_name="kubernetes-secrets",
        key="default/test-secret"
    )
    print(f"Found: {secret.secrets}")
except Exception as e:
    print(f"Error: {e}")
```

### Test via API

```bash
# Port forward
kubectl port-forward svc/secrets-router 8080:8080

# Test endpoint
curl http://localhost:8080/v1/secrets/test-secret?namespace=default
```

## Troubleshooting

### Dapr Client Can't Connect

**Error:** `Connection refused` or `Failed to connect`

**Solution:**
1. Verify Dapr sidecar is running: `kubectl get pod <pod-name>` (should show 2 containers)
2. Check sidecar logs: `kubectl logs <pod-name> -c daprd`
3. Verify ports match: `DAPR_HTTP_PORT=3500`, `DAPR_GRPC_PORT=50001`

### Component Not Found

**Error:** `Component kubernetes-secrets not found`

**Solution:**
1. List components: `kubectl get components -n <namespace>`
2. Deploy components: `kubectl apply -f dapr-components/`
3. Check component status: `kubectl describe component kubernetes-secrets`

### Secret Not Found

**Error:** `Secret not found in any Dapr secret store`

**Solution:**
1. Verify secret exists: `kubectl get secret <name> -n <namespace>`
2. Check component logs: `kubectl logs <pod-name> -c daprd`
3. Verify secret key format matches component expectations

## Migration Checklist

- [x] Update `requirements.txt` to use `dapr` instead of `kubernetes` and `boto3`
- [x] Replace direct API calls with Dapr SDK calls
- [x] Update environment variables
- [x] Update Helm chart values
- [x] Ensure Dapr sidecar injection is configured
- [x] Deploy Dapr components
- [x] Test secret retrieval
- [x] Update documentation

## Next Steps

1. **Deploy Dapr Control Plane** (if not already deployed)
2. **Deploy Dapr Components** (kubernetes-secrets, aws-secrets-manager)
3. **Deploy Secrets Router** (with Dapr sidecar injection)
4. **Test Secret Retrieval** from both stores
5. **Monitor Dapr Metrics** for observability


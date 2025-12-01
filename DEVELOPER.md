# Developer Guide

Quick guide for developers consuming secrets from the Secrets Router service.

## Quick Start

### 1. Deploy Secrets Router

```bash
# Build and deploy
make docker-build-all
helm install my-release ./charts/umbrella --create-namespace -n my-namespace
```

### 2. Define Your Service Secrets

In your `values.yaml` override file:

```yaml
services:
  my-service:
    secrets:
      database-credentials: "rds-credentials"
      api-keys: "/aws/prod/api-keys"
      redis-password: "production/redis-password"
```

### 3. Access Secrets in Your Application

```python
import requests

SECRETS_ROUTER_URL = "http://secrets-router:8080"
NAMESPACE = "my-namespace"

def get_secret(secret_name: str, secret_key: str) -> str:
    """Get secret value from Secrets Router."""
    url = f"{SECRETS_ROUTER_URL}/secrets/{secret_name}/{secret_key}"
    response = requests.get(url, params={"namespace": NAMESPACE})
    return response.json()["value"]

# Usage
db_password = get_secret("database-credentials", "password")
api_key = get_secret("api-keys", "external-service-key")
```

## API Endpoint

```
GET /secrets/{secret_name}/{secret_key}?namespace={namespace}
```

**Parameters:**
- `secret_name`: Name of the secret (e.g., "rds-credentials")
- `secret_key`: Key within the secret (e.g., "password")
- `namespace`: Kubernetes namespace where the secret lives

**Response:**
```json
{
  "backend": "kubernetes-secrets",
  "secret_name": "database-credentials", 
  "secret_key": "password",
  "value": "secret123"  // Always decoded and ready to use
}
```

## Common Commands

```bash
# Build all containers
make docker-build-all

# Deploy with custom secrets
helm upgrade my-release ./charts/umbrella -f my-secrets.yaml -n my-namespace

# Check deployment status
kubectl get pods -n my-namespace
kubectl logs -n my-namespace -l app.kubernetes.io/name=secrets-router

# Test secret access
kubectl exec -it <pod> -n my-namespace -- \
  curl "http://secrets-router:8080/secrets/my-secret/my-key?namespace=my-namespace"
```

## Configuration

### Secret Stores

Configure secret stores in `override.yaml`:

```yaml
secrets-router:
  secretStores:
    stores:
      kubernetes-secrets:
        namespaces:
          - my-namespace
          - shared-secrets
```

### Service Configuration

The umbrella chart allows you to specify which secrets each service needs:

```yaml
services:
  web-app:
    secrets:
      database-url: "production/db-credentials"
      jwt-secret: "auth/jwt-secret"
  
  backend-service:
    secrets:
      api-keys: "/aws/prod/api-keys"
      redis-password: "redis/credentials"
```

## Build Commands

```bash
# Build all containers
make docker-build-all

# Build only secrets-router
make docker-build-secrets-router

# Build only sample services
make docker-build-samples

# Package Helm charts
make helm-package
```

## Troubleshooting

### Secret Not Found (404)
1. Check if secret exists: `kubectl get secret my-secret -n my-namespace`
2. Verify namespace is configured in `secretStores.stores.kubernetes-secrets.namespaces`
3. Upgrade helm release with updated configuration

### Connection Issues
```bash
# Test connectivity
kubectl exec -it <pod> -n my-namespace -- curl http://secrets-router:8080/healthz
```

### Dapr Issues
```bash
# Check Dapr status
kubectl get pods -n dapr-system
kubectl get components -n my-namespace
```

That's it! You're ready to use Secrets Router in your applications.

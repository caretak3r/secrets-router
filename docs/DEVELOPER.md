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

In your `values.yaml` override file for the umbrella chart:

```yaml
# For Python service
sample-service-python:
  enabled: true
  secrets:
    rds-credentials: ""  # Replace with actual secret name or AWS path
    api-keys: ""         # Replace with actual secret name or AWS path

# For Node service  
sample-service-node:
  enabled: true
  secrets:
    rds-credentials: ""  # Replace with actual secret name or AWS path
    redis-password: ""   # Replace with actual secret name or AWS path

# For Bash service
sample-service-bash:
  enabled: true
  secrets:
    rds-credentials: ""  # Replace with actual secret name or AWS path
    shell-password: ""   # Replace with actual secret name or AWS path
```

**Note:** The secret values can be:
- Kubernetes secret names (e.g., "rds-credentials")
- AWS Secrets Manager paths (e.g., "/aws/prod/api-keys")
- Any other secret source supported by your configured secrets-router

### 3. Access Secrets in Your Application

Your applications access secrets via HTTP requests to the secrets-router service. The secret names are configured in the umbrella values.yaml:

```python
import os
import requests

def get_secret(secret_name: str, secret_key: str = "value") -> str:
    """Get secret value from Secrets Router."""
    secrets_router_url = os.getenv("SECRETS_ROUTER_URL")
    namespace = os.getenv("TEST_NAMESPACE")
    
    url = f"{secrets_router_url}/secrets/{secret_name}/{secret_key}"
    response = requests.get(url, params={"namespace": namespace})
    return response.json()["value"]

# Example usage with secret names from umbrella values.yaml
def get_database_credentials():
    """Get RDS credentials using the secret name from configuration."""
    # For Kubernetes secret named "rds-credentials"
    if not get_secret("rds-credentials", "host"):
        raise ValueError("Secret 'rds-credentials' not found")
    
    return {
        "host": get_secret("rds-credentials", "host"),
        "username": get_secret("rds-credentials", "username"), 
        "password": get_secret("rds-credentials", "password"),
        "database": get_secret("rds-credentials", "database")
    }

# For AWS Secrets Manager secret at "/aws/prod/api-keys"
def get_api_keys():
    """Get API keys from AWS Secrets Manager."""
    import json
    secret_json = get_secret("/aws/prod/api-keys", "value")
    return json.loads(secret_json)

# Usage
try:
    db_creds = get_database_credentials()
    print(f"Connecting to database: {db_creds['database']}")
    
    api_keys = get_api_keys()
    print(f"Retrieved {len(api_keys)} API keys")
except Exception as e:
    print(f"Error accessing secret: {e}")
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

The umbrella chart sets up each service with just the essential environment variables:

#### Environment Variables

Each service receives only these core environment variables:

- `SECRETS_ROUTER_URL`: URL of the secrets router service
- `TEST_NAMESPACE`: Kubernetes namespace where secrets are stored

#### Service Configuration Examples

```yaml
# Python service with AWS and Kubernetes secrets
sample-service-python:
  enabled: true
  secrets:
    rds-credentials: "prod-db-credentials"           # Kubernetes secret name
    api-keys: "/aws/production/api-keys"             # AWS Secrets Manager path
  
# Node service with mixed secret sources
sample-service-node:
  enabled: true
  secrets:
    redis-password: "redis-cluster-prod"            # Kubernetes secret name
    jwt-secret: "/prod/auth/jwt-secret"             # AWS Secrets Manager path

# Bash service with shell credentials
sample-service-bash:
  enabled: true
  secrets:
    rds-credentials: "prod-db-credentials"
    shell-password: "/ops/shell/secrets"
```

Services make HTTP requests to the secrets-router using the secret names configured above. The secrets-router will find and return the secret values from the appropriate backend (Kubernetes secrets or AWS Secrets Manager).

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
1. Check if secret exists: `kubectl get secret my-secret -n dapr-control-plane`
2. Verify namespace is configured in `secretStores.stores.kubernetes-secrets.namespaces`
3. Check that secret names match exactly between your values.yaml and application code
4. Upgrade helm release with updated configuration

### Connection Issues
```bash
# Test connectivity from service pod
kubectl exec -it <sample-pod> -n my-namespace -- \
  curl http://secrets-router.dapr-control-plane.svc.cluster.local:8080/healthz

# Check secrets router logs  
kubectl logs -n dapr-control-plane -l app.kubernetes.io/name=secrets-router
```

### Dapr Issues
```bash
# Check Dapr status
kubectl get pods -n dapr-system
kubectl get components -n dapr-control-plane

# Verify Dapr sidecar is running
kubectl get pods -n my-namespace -o wide | grep dapr
```

### Template Rendering Issues
```bash
# Test template rendering before deployment
helm template ./charts/umbrella --dry-run=client -f your-values.yaml

# Verify sample service manifests
helm template ./charts/umbrella --dry-run=client -f your-values.yaml | grep -A 20 "sample-service"
```

That's it! You're ready to use Secrets Router in your applications.

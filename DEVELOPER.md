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

Your applications can now access secrets using the automatically generated environment variables:

```python
import os
import requests

def get_secret(secret_path: str, secret_key: str = "value") -> str:
    """Get secret value from Secrets Router using environment-provided configuration."""
    secrets_router_url = os.getenv("SECRETS_ROUTER_URL")
    namespace = os.getenv("TEST_NAMESPACE")
    
    url = f"{secrets_router_url}/secrets/{secret_path}/{secret_key}"
    response = requests.get(url, params={"namespace": namespace})
    return response.json()["value"]

# Example using configured secrets
def get_database_credentials():
    """Get RDS credentials using the configured secret path."""
    rds_secret_path = os.getenv("SECRET_RDS_CREDENTIALS")
    if not rds_secret_path:
        raise ValueError("SECRET_RDS_CREDENTIALS not configured")
    
    # For Kubernetes secrets (single key)
    if not rds_secret_path.startswith("/"):
        return {
            "host": get_secret(f"{rds_secret_path}", "host"),
            "username": get_secret(f"{rds_secret_path}", "username"), 
            "password": get_secret(f"{rds_secret_path}", "password"),
            "database": get_secret(f"{rds_secret_path}", "database")
        }
    # For AWS Secrets Manager (JSON)
    else:
        import json
        secret_json = get_secret(rds_secret_path, "value")
        return json.loads(secret_json)

# Usage
db_creds = get_database_credentials()
print(f"Connecting to {db_creds['host']} as {db_creds['username']}")

# Alternative direct approach for individual secrets
available_secrets = os.getenv("AVAILABLE_SECRETS", "").split(",")
for secret_key in available_secrets:
    secret_path = os.getenv(f"SECRET_{secret_key.upper().replace('-', '_')}")
    secret_value = get_secret(secret_path)
    print(f"{secret_key}: {secret_value}")
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

The umbrella chart automatically sets up environment variables for each service based on their secrets configuration:

#### Environment Variables Generated

For each service, the following environment variables are automatically created:

- `SECRETS_ROUTER_URL`: URL of the secrets router service
- `TEST_NAMESPACE`: Kubernetes namespace where secrets are stored
- `SECRET_<SECRET_KEY>`: Path/name for each configured secret (normalized to uppercase with underscores)
- `AVAILABLE_SECRETS`: Comma-separated list of all available secret keys

#### Example Environment Variables

If you configure:

```yaml
sample-service-python:
  secrets:
    rds-credentials: "prod-rds-credentials"
    api-keys: "/aws/secrets/api-keys"
```

The Python service will receive these environment variables:

- `SECRETS_ROUTER_URL=http://secrets-router.dapr-control-plane.svc.cluster.local:8080`
- `TEST_NAMESPACE=dapr-control-plane`
- `SECRET_RDS_CREDENTIALS=prod-rds-credentials`
- `SECRET_API_KEYS=/aws/secrets/api-keys`
- `AVAILABLE_SECRETS=rds-credentials,api-keys`

#### Service Configuration Examples

```yaml
# Python service with AWS and Kubernetes secrets
sample-service-python:
  enabled: true
  secrets:
    rds-credentials: "prod-db-credentials"           # Kubernetes secret
    api-keys: "/aws/production/api-keys"             # AWS Secrets Manager
  
# Node service with mixed secret sources
sample-service-node:
  enabled: true
  secrets:
    redis-password: "redis-cluster-prod"            # Kubernetes secret
    jwt-secret: "/prod/auth/jwt-secret"             # AWS Secrets Manager

# Bash service with shell credentials
sample-service-bash:
  enabled: true
  secrets:
    rds-credentials: "prod-db-credentials"
    shell-password: "/ops/shell/secrets"
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

## Sample Service Environment Variables

When you deploy the sample services through the umbrella chart, they receive the following environment variables automatically:

### Python Service
```bash
# Generated from umbrella values.yaml
SECRETS_ROUTER_URL=http://secrets-router.dapr-control-plane.svc.cluster.local:8080
TEST_NAMESPACE=dapr-control-plane
SECRET_RDS_CREDENTIALS=your-rds-secret-name
SECRET_API_KEYS=your-api-keys-secret-name
AVAILABLE_SECRETS=rds-credentials,api-keys
```

### Node Service  
```bash
SECRETS_ROUTER_URL=http://secrets-router.dapr-control-plane.svc.cluster.local:8080
TEST_NAMESPACE=dapr-control-plane
SECRET_RDS_CREDENTIALS=your-rds-secret-name
SECRET_REDIS_PASSWORD=your-redis-secret-name
AVAILABLE_SECRETS=rds-credentials,redis-password
```

### Bash Service
```bash
SECRETS_ROUTER_URL=http://secrets-router.dapr-control-plane.svc.cluster.local:8080
TEST_NAMESPACE=dapr-control-plane
SECRET_RDS_CREDENTIALS=your-rds-secret-name
SECRET_SHELL_PASSWORD=your-shell-secret-name
AVAILABLE_SECRETS=rds-credentials,shell-password
```

## Troubleshooting

### Secret Not Found (404)
1. Check if secret exists: `kubectl get secret my-secret -n dapr-control-plane`
2. Verify namespace is configured in `secretStores.stores.kubernetes-secrets.namespaces`
3. Check that secret paths match exactly between your values.yaml and environment variables
4. Upgrade helm release with updated configuration

### Environment Variables Not Set
1. Verify service is enabled in umbrella values: `sample-service-python.enabled: true`
2. Check that secrets are configured under the correct service section
3. Use `kubectl exec -it <pod> -- env | grep SECRET` to examine environment variables
4. Ensure secrets are not empty strings in your values override

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

# Developer Guide

Quick guide for developers consuming secrets from the Secrets Router service.

## Prerequisite: Create Your Secrets

**Important**: You must create your Kubernetes secrets in the same namespace where you'll deploy the Secrets Router before installing the Helm chart. The Secrets Router service retrieves existing secrets but does not create them.

### Create Kubernetes Secrets

Create your secrets in the namespace where you'll deploy the Secrets Router:

```bash
# 1. Create your namespace (if it doesn't exist)
kubectl create namespace production

# 2. Create Kubernetes secrets in the same namespace
kubectl create secret generic rds-credentials \
  --from-literal=host=db.example.com \
  --from-literal=username=admin \
  --from-literal=password=secretpassword \
  --from-literal=database=production \
  -n production

kubectl create secret generic api-keys \
  --from-literal=key1=value1 \
  --from-literal=key2=value2 \
  -n production

# 3. Verify secrets exist
kubectl get secrets -n production
```

**Key Point**: All secrets must exist in the same namespace where you deploy the Secrets Router and your applications.

## Quick Start

### 1. Prepare Your Configuration

In your `values.yaml` override file, reference the Kubernetes secrets you created:

```yaml
# For Python service - reference your actual secret names
sample-service-python:
  enabled: true
  secrets:
    rds-credentials: "rds-credentials"           # Kubernetes secret name you created
    api-keys: "api-keys"                        # API keys secret you created

# For Node service  
sample-service-node:
  enabled: true
  secrets:
    rds-credentials: "rds-credentials"           # Same secret (can be reused)
    redis-password: "redis-credentials"         # Different secret

# For Bash service
sample-service-bash:
  enabled: true
  secrets:
    rds-credentials: "rds-credentials"           # Reused across services
    shell-password: "shell-credentials"         # Shell access secret
```

**Key Points:**
- **Secret Name**: Use the exact Kubernetes secret name you created
- **Reference Keys**: These are names your application code will use
- **Reuse Allowed**: Multiple services can reference the same secret
- **Namespace**: All secrets must be in the same namespace as the Secrets Router

### 2. Deploy Secrets Router

```bash
# Build and deploy
make docker-build-all
helm install my-release ./charts/umbrella --create-namespace -n production -f your-values.yaml
```

### 3. Access Secrets in Your Application

Your applications access secrets via HTTP requests to the secrets-router service. Use the secret names you configured in the values.yaml:

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
    if not get_secret("rds-credentials", "host"):
        raise ValueError("Secret 'rds-credentials' not found")
    
    return {
        "host": get_secret("rds-credentials", "host"),
        "username": get_secret("rds-credentials", "username"), 
        "password": get_secret("rds-credentials", "password"),
        "database": get_secret("rds-credentials", "database")
    }

def get_api_keys():
    """Get API keys from Kubernetes secret."""
    return get_secret("api-keys", "value")

# Usage
try:
    db_creds = get_database_credentials()
    print(f"Connecting to database: {db_creds['database']}")
    
    api_keys = get_api_keys()
    print(f"Retrieved API keys")
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

### Secret Store Setup

**No Manual Configuration Required**: The Secrets Router automatically accesses Kubernetes secrets in the same namespace where your services are deployed.

- **Kubernetes Secrets**: All secrets must be created in the same namespace as the Secrets Router
- **No Additional Setup**: Works out of the box with standard Kubernetes secrets
- **Single Namespace**: Simplified deployment model reduces configuration complexity

### Service Configuration

The umbrella chart sets up each service with just the essential environment variables:

#### Environment Variables

Each service receives only these core environment variables:

- `SECRETS_ROUTER_URL`: URL of the secrets router service
- `TEST_NAMESPACE`: Kubernetes namespace where secrets are stored

#### Service Configuration Examples

```yaml
# Python service
sample-service-python:
  enabled: true
  secrets:
    rds-credentials: "prod-db-credentials"           # Kubernetes secret name
    api-keys: "api-keys"                            # API keys secret
  
# Node service
sample-service-node:
  enabled: true
  secrets:
    redis-password: "redis-cluster-prod"            # Redis credentials secret
    jwt-secret: "jwt-credentials"                    # JWT token secret

# Bash service with shell credentials
sample-service-bash:
  enabled: true
  secrets:
    rds-credentials: "prod-db-credentials"
    shell-password: "shell-credentials"
```

Services make HTTP requests to the secrets-router using the secret names configured above. All secrets must be Kubernetes secrets in the same namespace as the deployedservices.

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
1. **Verify Secret Creation**: Ensure you created the secret in the deployment namespace:
   ```bash
   kubectl get secret rds-credentials -n production
   ```
2. **Check Configuration**: Verify the secret name in your values.yaml matches exactly what you created
3. **Namespace Match**: Ensure all secrets are in the same namespace where you deploy the Secrets Router
4. **Test Access**: Try accessing the secret directly from a pod to verify connectivity
5. **Upgrade if Needed**: Update your Helm release if configuration changes were made
6. **List All Secrets**: Check what secrets are available in the namespace:
   ```bash
   kubectl get secrets -n production
   ```

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

## Development and Testing Workflow

### Step-by-Step Testing Process

1. **Create Test Secrets** (Prerequisite)
   ```bash
   # Create namespace for testing
   kubectl create namespace test-namespace
   
   # Create test Kubernetes secret
   kubectl create secret generic test-secret \
     --from-literal=password=testpass123 \
     --from-literal=username=testuser \
     -n test-namespace
   ```

2. **Configure Your Service** 
   ```yaml
   sample-service-python:
     enabled: true
     secrets:
       test-secret: "test-secret"  # Reference to the secret you created
   ```

3. **Deploy and Test**
   ```bash
   # Deploy the umbrella chart
   helm install test-release ./charts/umbrella \
     --create-namespace -n test-namespace \
     -f your-test-values.yaml
   
   # Test secret access
   kubectl exec -it deployment/sample-service-python -n test-namespace -- \
     curl "http://secrets-router:8080/secrets/test-secret/password?namespace=test-namespace"
   ```

### Best Practices for Testing

- **Use Separate Namespaces**: Create dedicated namespaces for testing to avoid conflicts with production secrets
- **Validate Each Secret**: Test individual secret keys to ensure data integrity
- **Error Handling**: Verify your applications handle secret access failures gracefully
- **Simple Setup**: Use only Kubernetes secrets in the same namespace as your services

That's it! You're ready to use Secrets Router in your applications.

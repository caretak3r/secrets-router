# Developer Guide

Quick guide for developers consuming secrets from the Secrets Router service.

## Prerequisite: Create Your Secrets

**Important**: You must create your secrets before deploying the Helm chart. The Secrets Router service retrieves existing secrets but does not create them.

### For Kubernetes Secrets

If you're storing secrets in Kubernetes, create them first:

```bash
# 1. Create your namespace (if it doesn't exist)
kubectl create namespace my-namespace

# 2. Create Kubernetes secrets in your namespace
kubectl create secret generic rds-credentials \
  --from-literal=host=db.example.com \
  --from-literal=username=admin \
  --from-literal=password=secretpassword \
  --from-literal=database=production \
  -n my-namespace

kubectl create secret generic api-keys \
  --from-literal=key1=value1 \
  --from-literal=key2=value2 \
  -n my-namespace

# 3. Verify secrets exist
kubectl get secrets -n my-namespace
```

### For AWS Secrets Manager

If you're using AWS Secrets Manager, create the secrets in AWS first:

```bash
# Example using AWS CLI
aws secretsmanager create-secret \
  --name "/aws/prod/api-keys" \
  --secret-string '{"key1":"value1","key2":"value2"}' \
  --region us-east-1

# Example database credentials
aws secretsmanager create-secret \
  --name "prod-db-credentials" \
  --secret-string '{"host":"db.example.com","username":"admin","password":"secretpassword","database":"production"}' \
  --region us-east-1
```

### Secret Store Configuration

**No Additional Configuration Required**: You do not need to configure a secret store in Kubernetes. The Secrets Router automatically supports both:
- **Kubernetes Secrets**: Access secrets within the same namespace
- **AWS Secrets Manager**: Access secrets using AWS IAM roles or credentials

The Secrets Router will automatically determine the appropriate backend based on the secret path/name provided in your configuration.

## Quick Start

### 1. Prepare Your Configuration

In your `values.yaml` override file, reference the secrets you created:

```yaml
# For Python service - reference your actual secret names/paths
sample-service-python:
  enabled: true
  secrets:
    rds-credentials: "rds-credentials"           # Kubernetes secret name you created
    api-keys: "/aws/prod/api-keys"              # AWS Secrets Manager path you created

# For Node service
sample-service-node:
  enabled: true
  secrets:
    rds-credentials: "rds-credentials"           # Same Kubernetes secret (can be reused)
    redis-password: "redis-credentials"           # Different secret name

# For Bash service
sample-service-bash:
  enabled: true
  secrets:
    rds-credentials: "rds-credentials"           # Same secret reused across services
    shell-password: "shell-credentials"         # Shell access credentials
```

**Key Points:**
- **Secret Values**: Use the actual secret names (Kubernetes) or paths (AWS) you created in the prerequisite steps
- **Secret Keys**: These are reference names for your application code
- **Reuse Allowed**: Multiple services can reference the same secret

### 2. Deploy Secrets Router

```bash
# Build and deploy
make docker-build-all
helm install my-release ./charts/umbrella --create-namespace -n my-namespace -f your-values.yaml
```

### 3. Define Your Service Secrets (Optional Override)

You can also define secrets directly in an override file instead of the umbrella values.yaml:

```yaml
# Test configuration using secrets you created
sample-service-python:
  enabled: true
  secrets:
    rds-credentials: "rds-credentials"      # Actual Kubernetes secret you created
    api-keys: "/aws/prod/api-keys"         # Actual AWS Secrets Manager path you created

sample-service-node:  
  enabled: true
  secrets:
    rds-credentials: "rds-credentials"      # Reuse same secret
    redis-password: "redis-credentials"     # Different secret

sample-service-bash:
  enabled: true
  secrets:
    rds-credentials: "rds-credentials"      # Same secret referenced by multiple services
    shell-password: "shell-credentials"     # Shell access secret
```

### 4. Access Secrets in Your Application

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

### Secret Store Setup

**No Manual Configuration Required**: The Secrets Router automatically detects and uses the appropriate secret store based on how you reference your secrets:

- **Kubernetes Secrets**: When you reference a secret name (e.g., `"rds-credentials"`)
  - Automatically looks for Kubernetes secrets in your deployment namespace
  - No additional configuration needed

- **AWS Secrets Manager**: When you reference a path (e.g., `"/aws/prod/api-keys"`)
  - Automatically routes to AWS Secrets Manager
  - Uses IAM roles or configured AWS credentials
  - No additional configuration needed

### Optional Namespace Configuration (Advanced)

If you need to access Kubernetes secrets in multiple namespaces from a single deployment, you can specify additional namespaces:

```yaml
secrets-router:
  secretStores:
    stores:
      kubernetes-secrets:
        namespaces:
          - my-namespace          # Default deployment namespace (always included)
          - shared-secrets        # Additional namespace for shared secrets
          - configuration         # Configuration secrets namespace
```

**Note**: For most use cases, you don't need this configuration. Simply create all your Kubernetes secrets in the same namespace where you deploy your services.

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
1. **Verify Secret Creation**: Ensure you created the secret in the correct location:
   ```bash
   # For Kubernetes secrets
   kubectl get secret rds-credentials -n my-namespace
   
   # For AWS Secrets Manager
   aws secretsmanager describe-secret --name "/aws/prod/api-keys"
   ```
2. **Check Configuration**: Verify the secret name/path in your values.yaml matches exactly what you created
3. **Namespace Match**: Ensure you're referencing secrets in the same namespace where your services are deployed
4. **Test Access**: Try accessing the secret directly from a pod to verify connectivity
5. **Upgrade if Needed**: Update your Helm release if configuration changes were made

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
- **Test Both Backends**: Verify access to both Kubernetes secrets and AWS Secrets Manager (if applicable)
- **Validate Each Secret**: Test individual secret keys to ensure data integrity
- **Error Handling**: Verify your applications handle secret access failures gracefully

That's it! You're ready to use Secrets Router in your applications.

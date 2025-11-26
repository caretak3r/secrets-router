# Developer Guide: Consuming Secrets

This guide shows developers how to configure and consume secrets from the Secrets Router service in their applications.

## Overview

The Secrets Router service provides a simple HTTP API to fetch secrets from Kubernetes Secrets or AWS Secrets Manager. Secrets can be accessed from **multiple namespaces** - you configure which namespaces are accessible via Helm values in the `control-plane-umbrella` chart.

## Architecture Context

The Secrets Router is deployed as part of the `control-plane-umbrella` Helm chart:
- **Umbrella Chart**: `control-plane-umbrella` installs Dapr and Secrets Router
- **Secrets Router Chart**: Has dependency on Dapr, generates Dapr Component resources
- **Dapr Components**: Configured via `secrets-components.yaml` template from Helm values
- **Namespace**: All resources use `{{ .Release.Namespace }}` (no hardcoded namespaces)

## Quick Start

### 1. Basic Secret Retrieval

```bash
# Get a secret value (always decoded and ready to use)
curl http://secrets-router:8080/secrets/my-secret/database-password?namespace=production
```

### 2. Response Format

```json
{
  "backend": "kubernetes-secrets",
  "secret_name": "my-secret",
  "secret_key": "database-password",
  "value": "password123"  // Always decoded and ready to use
}
```

## API Endpoint

```
GET /secrets/{secret_name}/{secret_key}?namespace={namespace}
```

### Parameters

- **`secret_name`** (path, required): Name of the Kubernetes Secret or AWS Secrets Manager secret. Can be a simple name (e.g., `database-credentials`) or a full path (e.g., `/app/secrets/production/database-credentials`). For AWS secrets, paths can be configured in Helm chart values.
- **`secret_key`** (path, required): Key within the secret to retrieve
- **`namespace`** (query, required): Kubernetes namespace where the secret is stored (used for Kubernetes secrets)

## Examples

### Python Example

```python
import requests
import base64

# Service URL (use service name in Kubernetes)
SECRETS_ROUTER_URL = "http://secrets-router:8080"
NAMESPACE = "production"  # Your application namespace

def get_secret(secret_name: str, secret_key: str) -> str:
    """
    Get secret value from Secrets Router.
    
    Args:
        secret_name: Name of the secret
        secret_key: Key within the secret
    
    Returns:
        Secret value as decoded string, ready to use
    """
    url = f"{SECRETS_ROUTER_URL}/secrets/{secret_name}/{secret_key}"
    params = {"namespace": NAMESPACE}
    
    response = requests.get(url, params=params)
    response.raise_for_status()
    
    data = response.json()
    return data["value"]

# Usage
db_password = get_secret("database-credentials", "password")
api_key = get_secret("api-keys", "external-service-key")
```

### Go Example

```go
package main

import (
    "encoding/json"
    "fmt"
    "net/http"
    "net/url"
)

type SecretResponse struct {
    Backend    string `json:"backend"`
    SecretName string `json:"secret_name"`
    SecretKey  string `json:"secret_key"`
    Value      string `json:"value"`
}

func getSecret(secretRouterURL, namespace, secretName, secretKey string) (string, error) {
    u, err := url.Parse(fmt.Sprintf("%s/secrets/%s/%s", secretRouterURL, secretName, secretKey))
    if err != nil {
        return "", err
    }
    
    q := u.Query()
    q.Set("namespace", namespace)
    u.RawQuery = q.Encode()
    
    resp, err := http.Get(u.String())
    if err != nil {
        return "", err
    }
    defer resp.Body.Close()
    
    if resp.StatusCode != http.StatusOK {
        return "", fmt.Errorf("failed to get secret: %d", resp.StatusCode)
    }
    
    var secretResp SecretResponse
    if err := json.NewDecoder(resp.Body).Decode(&secretResp); err != nil {
        return "", err
    }
    
    return secretResp.Value, nil
}

func main() {
    password, err := getSecret(
        "http://secrets-router:8080",
        "production",
        "database-credentials",
        "password",
    )
    if err != nil {
        panic(err)
    }
    fmt.Println("Password:", password)
}
```

### Node.js/TypeScript Example

```typescript
import axios from 'axios';

const SECRETS_ROUTER_URL = 'http://secrets-router:8080';
const NAMESPACE = 'production';

interface SecretResponse {
  backend: string;
  secret_name: string;
  secret_key: string;
  value: string;
}

async function getSecret(
  secretName: string,
  secretKey: string
): Promise<string> {
  const response = await axios.get<SecretResponse>(
    `${SECRETS_ROUTER_URL}/secrets/${secretName}/${secretKey}`,
    {
      params: {
        namespace: NAMESPACE,
      },
    }
  );
  
  return response.data.value;
}

// Usage
const dbPassword = await getSecret('database-credentials', 'password');
const apiKey = await getSecret('api-keys', 'external-service-key');
```

## Configuring Secret Stores

### Step 1: Create Your Secrets

Create secrets in any namespace where your application needs them:

```bash
# Create secret in production namespace
kubectl create secret generic database-credentials \
  --from-literal=password=secret123 \
  --from-literal=username=admin \
  -n production

# Create secret in staging namespace
kubectl create secret generic database-credentials \
  --from-literal=password=staging123 \
  --from-literal=username=admin \
  -n staging
```

### Step 2: Configure Secret Stores in override.yaml

Update the `override.yaml` file used with the `control-plane-umbrella` chart to include namespaces where secrets can be accessed:

```yaml
# override.yaml
secrets-router:
  enabled: true
  
  # Configure which namespaces secrets can be accessed from
  secretStores:
    enabled: true
    stores:
      kubernetes-secrets:
        type: secretstores.kubernetes
        defaultSecretStore: true
        # Add namespaces where secrets exist
        namespaces:
          - production
          - staging
          - shared-services  # Add any namespace with secrets
      
      aws-secrets-manager:
        type: secretstores.aws.secretsmanager
        defaultSecretStore: false
        region: us-east-1
        pathPrefix: "/app/secrets"
        auth:
          secretStore: kubernetes
```

### Step 3: Upgrade Helm Release

Apply the configuration:

```bash
helm upgrade control-plane ./charts/umbrella -f override.yaml -n <namespace>
```

This will:
1. Generate Dapr Component resources for the configured secret stores
2. Update the Secrets Router to access secrets from the specified namespaces

### Step 4: Access Secrets from Applications

Applications can now access secrets from any configured namespace:

```python
# Access secret from production namespace
password = get_secret("database-credentials", "password", namespace="production")

# Access secret from staging namespace  
password = get_secret("database-credentials", "password", namespace="staging")
```

## Secret Storage Locations

### Kubernetes Secrets

Secrets stored as Kubernetes Secrets are accessed using:
- **Format**: `namespace/secret-name` (namespace specified in API call)
- **Location**: Any namespace configured in `override.yaml` → `secretStores.stores.kubernetes-secrets.namespaces`
- **Auto-decoding**: K8s secrets are automatically decoded (base64 → plain text)

**Example:**
```bash
# Secret exists in Kubernetes:
kubectl get secret database-credentials -n production

# Ensure namespace is in override.yaml secretStores configuration
# Then access via API:
GET /secrets/database-credentials/password?namespace=production
```

### AWS Secrets Manager

Secrets stored in AWS Secrets Manager are accessed using:
- **Format**: Full path (with optional `pathPrefix` configured in Helm values)
- **Location**: AWS Secrets Manager
- **Configuration**: Configured in `override.yaml` → `secretStores.stores.aws-secrets-manager`

**Example:**
```yaml
# In override.yaml:
aws-secrets-manager:
  pathPrefix: "/app/secrets"
```

```bash
# Access via API (pathPrefix is prepended):
GET /secrets/production/database-credentials/password?namespace=production
# Resolves to: /app/secrets/production/database-credentials
```

## Secret Resolution Priority

The service tries secret stores in this order (configured via `SECRET_STORE_PRIORITY`):

1. **Kubernetes Secrets** (checks all configured namespaces in order)
2. **AWS Secrets Manager** (if configured)

If a secret is found in Kubernetes, it's returned immediately. If not found, AWS Secrets Manager is checked.

**Note**: The `kubernetes-secrets` component checks namespaces in the order specified in `override.yaml`. If a secret exists in multiple namespaces, the first match is returned.

## Best Practices

### 1. Use Environment Variables for Configuration

```python
import os

SECRETS_ROUTER_URL = os.getenv("SECRETS_ROUTER_URL", "http://secrets-router:8080")
NAMESPACE = os.getenv("NAMESPACE", "default")  # Usually set by Kubernetes
```

### 2. Cache Secrets When Appropriate

```python
from functools import lru_cache

@lru_cache(maxsize=100)
def get_cached_secret(secret_name: str, secret_key: str) -> str:
    """Cache secret values to reduce API calls."""
    return get_secret(secret_name, secret_key)
```

### 3. Handle Errors Gracefully

```python
import requests
from requests.exceptions import RequestException

def get_secret_safe(secret_name: str, secret_key: str, default: str = None) -> str:
    """Get secret with fallback to default value."""
    try:
        return get_secret(secret_name, secret_key)
    except RequestException as e:
        logger.warning(f"Failed to get secret {secret_name}/{secret_key}: {e}")
        if default:
            return default
        raise
```

### 4. Values Are Always Decoded

All secret values are automatically decoded and ready to use:

```python
# Values are always decoded - ready to use immediately
password = get_secret("database-credentials", "password")
api_key = get_secret("api-keys", "external-service")
```

## Common Patterns

### Application Startup

```python
# Load secrets at startup
class Config:
    def __init__(self):
        self.db_password = get_secret("database-credentials", "password")
        self.api_key = get_secret("api-keys", "external-service")
        self.redis_password = get_secret("redis-credentials", "password")

config = Config()
```

### Lazy Loading

```python
class SecretManager:
    def __init__(self):
        self._cache = {}
    
    def get(self, secret_name: str, secret_key: str) -> str:
        cache_key = f"{secret_name}:{secret_key}"
        if cache_key not in self._cache:
            self._cache[cache_key] = get_secret(secret_name, secret_key)
        return self._cache[cache_key]
```

## Troubleshooting

### Secret Not Found (404)

**Check 1: Verify secret exists**
```bash
# Check if secret exists in namespace
kubectl get secret my-secret -n production
```

**Check 2: Verify namespace is configured**
```bash
# Check Dapr Component configuration
kubectl get component kubernetes-secrets -n <release-namespace> -o yaml

# Verify namespace is in allowedNamespaces list
```

**Check 3: Update override.yaml if namespace missing**
```yaml
# Add missing namespace to override.yaml
secretStores:
  stores:
    kubernetes-secrets:
      namespaces:
        - production  # Add this if missing
        - staging
```

**Check 4: Upgrade helm release**
```bash
helm upgrade control-plane ./charts/umbrella -f override.yaml
```

### Wrong Namespace

Make sure you're using the correct namespace where your application is deployed:

```python
# Get namespace from Kubernetes downward API
NAMESPACE = open('/var/run/secrets/kubernetes.io/serviceaccount/namespace').read().strip()
```

**Also verify**: The namespace you're querying is in the `secretStores.stores.kubernetes-secrets.namespaces` list in `override.yaml`.

### Component Not Found

If Dapr Component is not created:

1. **Check if secretStores.enabled is true**:
   ```yaml
   secretStores:
     enabled: true  # Must be true
   ```

2. **Verify helm template renders correctly**:
   ```bash
   helm template control-plane ./charts/umbrella -f override.yaml | grep -A 20 "kind: Component"
   ```

3. **Check component exists after install**:
   ```bash
   kubectl get components -n <release-namespace>
   ```

### Connection Issues

```bash
# Test connectivity from your pod
kubectl exec -it <your-pod> -n <namespace> -- \
  curl http://secrets-router:8080/healthz
```

## Security Considerations

1. **Never log secret values** - Always mask secrets in logs
2. **Use HTTPS in production** - Configure TLS for secrets-router service
3. **Namespace isolation** - Secrets are namespace-scoped, providing isolation
4. **RBAC** - Ensure your ServiceAccount has proper RBAC permissions

## Integration with Service Helm Charts

If your service helm chart is part of the `control-plane-umbrella`:

### Option 1: Runtime Secret Fetching (Recommended)

```python
# In your application code
import requests
import os

SECRETS_ROUTER_URL = os.getenv("SECRETS_ROUTER_URL", "http://secrets-router:8080")
NAMESPACE = os.getenv("NAMESPACE")  # Set via downward API

def get_secret(secret_name: str, secret_key: str) -> str:
    url = f"{SECRETS_ROUTER_URL}/secrets/{secret_name}/{secret_key}"
    params = {"namespace": NAMESPACE}
    response = requests.get(url, params=params)
    response.raise_for_status()
    return response.json()["value"]
```

### Option 2: Init Container Pattern

```yaml
# In your service helm chart deployment.yaml
initContainers:
- name: fetch-secrets
  image: curlimages/curl:latest
  command:
    - sh
    - -c
    - |
      DB_PASSWORD=$(curl -s "http://secrets-router:8080/secrets/database-credentials/password?namespace={{ .Release.Namespace }}" | jq -r '.value')
      echo "export DB_PASSWORD=$DB_PASSWORD" > /shared/secrets.sh
  volumeMounts:
    - name: shared-secrets
      mountPath: /shared
```

### Option 3: Environment Variable Injection

```yaml
# In your service helm chart deployment.yaml
containers:
- name: app
  env:
  - name: SECRETS_ROUTER_URL
    value: "http://secrets-router:8080"
  - name: NAMESPACE
    valueFrom:
      fieldRef:
        fieldPath: metadata.namespace
```

## Migration from Direct Secret Access

If you're currently mounting secrets as volumes:

**Before:**
```yaml
volumes:
- name: secrets
  secret:
    secretName: database-credentials
```

**After:**
1. Ensure namespace is configured in `override.yaml`
2. Use Secrets Router API:
```python
# Use Secrets Router API - values are always decoded
password = get_secret("database-credentials", "password", namespace="production")
```

## Support

For issues or questions:
- Check logs: `kubectl logs -n <namespace> -l app.kubernetes.io/name=secrets-router`
- Verify Dapr components: `kubectl get components -n <namespace>`
- Review ADR: See `ADR.md` for architecture details


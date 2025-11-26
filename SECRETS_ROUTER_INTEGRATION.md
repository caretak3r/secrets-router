# Secrets Router Integration Guide

## Overview

This guide explains how individual service Helm charts that are part of the `control-plane-umbrella` can use secrets managed by the Secrets Router service.

## Architecture Summary

```
control-plane-umbrella (umbrella chart)
├── dapr (dependency)
│   └── Dapr control plane components
└── secrets-router (dependency)
    ├── secrets-router service deployment
    └── secrets-components.yaml (generates Dapr Component resources)
```

**Key Points:**
- Secrets Router is deployed as part of the umbrella chart
- Dapr Components are **generated** from Helm values via `secrets-components.yaml` template
- Developers configure secret locations via `override.yaml` file
- All resources use `{{ .Release.Namespace }}` (no hardcoded namespaces)

## Developer Workflow

### Step 1: Create Secrets

Developers create secrets in any namespace where they're needed:

```bash
# Create secret in production namespace
kubectl create secret generic database-credentials \
  --from-literal=password=secret123 \
  --from-literal=username=admin \
  -n production

# Create secret in shared-services namespace
kubectl create secret generic shared-api-key \
  --from-literal=key=abc123 \
  -n shared-services
```

### Step 2: Configure Secret Stores

The umbrella chart `values.yaml` contains only enable/disable flags. Default configurations are in `charts/secrets-router/values.yaml`.

Update `override.yaml` to customize secret store namespaces:

```yaml
# override.yaml
# Only override what you need to customize
# Defaults come from charts/secrets-router/values.yaml

secrets-router:
  # Override secret store namespaces
  secretStores:
    stores:
      kubernetes-secrets:
        # List namespaces where Kubernetes secrets can be accessed
        namespaces:
          - production
          - staging
          - shared-services  # Add namespace where secret exists
  
  # Override other settings as needed (optional)
  # See charts/secrets-router/values.yaml for all options
```

### Step 3: Upgrade Helm Release

Apply the configuration:

```bash
helm upgrade control-plane ./charts/umbrella -f override.yaml -n <namespace>
```

This generates Dapr Component resources that allow Secrets Router to access secrets from the configured namespaces.

### Step 4: Use Secrets in Service Helm Charts

Individual service Helm charts can access secrets in several ways:

#### Option 1: HTTP API Call (Recommended)

```python
# In your application code
import requests
import os

SECRETS_ROUTER_URL = os.getenv("SECRETS_ROUTER_URL", "http://secrets-router:8080")
NAMESPACE = os.getenv("NAMESPACE")  # Set via downward API

def get_secret(secret_name: str, secret_key: str, namespace: str = None) -> str:
    """Get secret from Secrets Router."""
    if namespace is None:
        namespace = NAMESPACE
    
    url = f"{SECRETS_ROUTER_URL}/secrets/{secret_name}/{secret_key}"
    params = {"namespace": namespace}
    
    response = requests.get(url, params=params)
    response.raise_for_status()
    
    return response.json()["value"]

# Usage
db_password = get_secret("database-credentials", "password", namespace="production")
api_key = get_secret("shared-api-key", "key", namespace="shared-services")
```

#### Option 2: Init Container Pattern

```yaml
# In your service helm chart deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "my-service.fullname" . }}
spec:
  template:
    spec:
      initContainers:
      - name: fetch-secrets
        image: curlimages/curl:latest
        command:
          - sh
          - -c
          - |
            DB_PASSWORD=$(curl -s "http://secrets-router:8080/secrets/database-credentials/password?namespace=production" | jq -r '.value')
            echo "export DB_PASSWORD=$DB_PASSWORD" > /shared/secrets.sh
        volumeMounts:
          - name: shared-secrets
            mountPath: /shared
      containers:
      - name: app
        env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: fetched-secrets
              key: db-password
```

#### Option 3: Environment Variable Injection

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
  # Application code fetches secrets at runtime using these env vars
```

## How It Works

### 1. Component Generation

When you install/upgrade the umbrella chart with `override.yaml`:

1. Helm merges values: `umbrella/values.yaml` (defaults) + `override.yaml` (customizations)
2. Child chart defaults from `secrets-router/values.yaml` are used unless overridden
3. Helm processes `secrets-components.yaml` template
4. Template generates Dapr Component resources based on `secretStores.stores` values
5. Components are created in `{{ .Release.Namespace }}`
6. Components configure which namespaces secrets can be accessed from

### 2. Secret Access Flow

```
Application Pod
    ↓ HTTP GET /secrets/{name}/{key}?namespace={ns}
Secrets Router Service
    ↓ HTTP GET localhost:3500/v1.0/secrets/{store}/{key}
Dapr Sidecar
    ↓ Component API
Dapr Component (kubernetes-secrets)
    ↓ Checks allowedNamespaces
Kubernetes API
    ↓ Read secret from namespace
Kubernetes Secret
```

### 3. Multi-Namespace Support

The `kubernetes-secrets` Dapr Component is configured with `allowedNamespaces` metadata:

```yaml
metadata:
- name: allowedNamespaces
  value: "production,staging,shared-services"
```

This allows the component to access secrets from any namespace in the list.

## Example: Service Helm Chart Integration

### Service Chart Structure

```
my-service/
├── Chart.yaml
├── values.yaml
└── templates/
    └── deployment.yaml
```

### Service Chart values.yaml

```yaml
# Service-specific values
image:
  repository: my-service
  tag: latest

# Secrets configuration
secrets:
  database:
    name: database-credentials
    namespace: production
  api:
    name: shared-api-key
    namespace: shared-services
```

### Service Chart deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "my-service.fullname" . }}
spec:
  template:
    spec:
      containers:
      - name: app
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        env:
        - name: SECRETS_ROUTER_URL
          value: "http://secrets-router:8080"
        - name: NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: DB_SECRET_NAME
          value: {{ .Values.secrets.database.name | quote }}
        - name: DB_SECRET_NAMESPACE
          value: {{ .Values.secrets.database.namespace | quote }}
        # Application fetches secrets at runtime using these env vars
```

### Application Code

```python
import os
import requests

def get_secret(secret_name: str, secret_key: str, namespace: str) -> str:
    """Get secret from Secrets Router."""
    router_url = os.getenv("SECRETS_ROUTER_URL", "http://secrets-router:8080")
    url = f"{router_url}/secrets/{secret_name}/{secret_key}"
    params = {"namespace": namespace}
    
    response = requests.get(url, params=params)
    response.raise_for_status()
    
    return response.json()["value"]

# At application startup
db_password = get_secret(
    os.getenv("DB_SECRET_NAME"),
    "password",
    os.getenv("DB_SECRET_NAMESPACE")
)
```

## Adding New Secret Locations

When a developer needs to access secrets from a new namespace:

1. **Create the secret**:
   ```bash
   kubectl create secret generic my-secret \
     --from-literal=key=value \
     -n new-namespace
   ```

2. **Update override.yaml**:
   ```yaml
   secrets-router:
     secretStores:
       stores:
         kubernetes-secrets:
           namespaces:
             - production
             - staging
             - new-namespace  # Add this
   ```

3. **Upgrade helm release**:
   ```bash
   helm upgrade control-plane ./charts/umbrella -f override.yaml
   ```

4. **Use in application**:
   ```python
   secret_value = get_secret("my-secret", "key", namespace="new-namespace")
   ```

**No code changes needed** - just update `override.yaml` and upgrade!

## Benefits

1. **Streamlined Configuration**: Update `override.yaml` to add new secret locations
2. **No Code Changes**: Adding new namespaces doesn't require code changes
3. **Multi-Namespace Support**: Access secrets from multiple namespaces
4. **Centralized Management**: All secret access goes through Secrets Router
5. **Audit Trail**: All secret access is logged by Secrets Router
6. **Auto-Decoding**: Kubernetes secrets automatically decoded
7. **Flexible**: Supports both Kubernetes Secrets and AWS Secrets Manager

## Troubleshooting

### Secret Not Found

1. **Verify secret exists**:
   ```bash
   kubectl get secret my-secret -n production
   ```

2. **Check namespace is configured**:
   ```bash
   kubectl get component kubernetes-secrets -n <release-namespace> -o yaml
   # Look for allowedNamespaces metadata
   ```

3. **Verify namespace in override.yaml**:
   ```yaml
   secretStores:
     stores:
       kubernetes-secrets:
         namespaces:
           - production  # Must include this
   ```

4. **Upgrade helm release**:
   ```bash
   helm upgrade control-plane ./charts/umbrella -f override.yaml
   ```

### Component Not Created

1. **Check secretStores.enabled**:
   ```yaml
   secretStores:
     enabled: true  # Must be true
   ```

2. **Verify template renders**:
   ```bash
   helm template control-plane ./charts/umbrella -f override.yaml | grep -A 20 "kind: Component"
   ```

3. **Check component exists**:
   ```bash
   kubectl get components -n <release-namespace>
   ```

## Summary

The Secrets Router integration provides a streamlined way for developers to:

1. **Create secrets** wherever they need them (any namespace)
2. **Configure access** via `override.yaml` (add namespaces to the list)
3. **Use secrets** in their applications via HTTP API calls
4. **No code changes** needed when adding new secret locations - just update `override.yaml` and upgrade the helm release

This approach provides flexibility while maintaining security and auditability.


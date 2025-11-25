# Quick Start Guide

Get the Secrets Broker up and running in your Kubernetes cluster in minutes.

## Prerequisites

- Kubernetes cluster (1.24+)
- Helm 3.x
- kubectl configured
- (Optional) AWS credentials/IRSA if using AWS Secrets Manager

## Installation

### Step 1: Build Docker Image

```bash
cd k8s-secrets-broker

# Build image
make build

# Or with custom registry
make build IMAGE_REGISTRY=your-registry.io IMAGE_TAG=v1.0.0

# Build and push
make build-push IMAGE_REGISTRY=your-registry.io IMAGE_TAG=v1.0.0
```

### Step 2: Install Umbrella Chart

```bash
# Install in your namespace
helm install secrets-broker ./charts/umbrella \
  --namespace production \
  --create-namespace \
  --set global.namespace=production \
  --set secrets-router.image.repository=your-registry.io/secrets-router \
  --set secrets-router.image.tag=v1.0.0
```

### Step 3: Deploy Dapr Components

```bash
# Deploy Kubernetes Secrets component
kubectl apply -f dapr-components/kubernetes-secrets-component.yaml -n production

# Deploy AWS Secrets Manager component (if using AWS)
kubectl apply -f dapr-components/aws-secrets-manager-component.yaml -n production
```

### Step 4: Verify Installation

```bash
# Check pods
kubectl get pods -n production

# Check Dapr control plane
kubectl get pods -n dapr-system

# Check components
kubectl get components -n production

# Check service
kubectl get svc -n production secrets-router
```

### Step 5: Test Secret Retrieval

```bash
# Create a test secret
kubectl create secret generic test-secret \
  --from-literal=password=test123 \
  -n production

# Port forward
kubectl port-forward -n production svc/secrets-router 8080:8080

# Test API
curl "http://localhost:8080/secrets/test-secret/password?namespace=production&decode=true"
```

## Using in Your Application

### Python Example

```python
import requests
import os

SECRETS_ROUTER_URL = os.getenv("SECRETS_ROUTER_URL", "http://secrets-router:8080")
NAMESPACE = os.getenv("NAMESPACE", "production")  # Set by Kubernetes

def get_secret(secret_name: str, secret_key: str) -> str:
    url = f"{SECRETS_ROUTER_URL}/secrets/{secret_name}/{secret_key}"
    response = requests.get(url, params={"namespace": NAMESPACE, "decode": "true"})
    response.raise_for_status()
    return response.json()["value"]

# Usage
db_password = get_secret("database-credentials", "password")
```

### Go Example

```go
package main

import (
    "encoding/json"
    "fmt"
    "net/http"
    "net/url"
    "os"
)

func getSecret(secretName, secretKey, namespace string) (string, error) {
    routerURL := os.Getenv("SECRETS_ROUTER_URL")
    if routerURL == "" {
        routerURL = "http://secrets-router:8080"
    }
    
    u, _ := url.Parse(fmt.Sprintf("%s/secrets/%s/%s", routerURL, secretName, secretKey))
    q := u.Query()
    q.Set("namespace", namespace)
    q.Set("decode", "true")
    u.RawQuery = q.Encode()
    
    resp, err := http.Get(u.String())
    if err != nil {
        return "", err
    }
    defer resp.Body.Close()
    
    var result map[string]interface{}
    json.NewDecoder(resp.Body).Decode(&result)
    return result["value"].(string), nil
}
```

## Configuration

### Custom AWS Path Prefix

```yaml
# In umbrella chart values.yaml
secrets-router:
  env:
    AWS_SECRETS_PATH_PREFIX: "/mycompany/secrets"
```

### Custom Secret Store Priority

```yaml
# In umbrella chart values.yaml
secrets-router:
  env:
    SECRET_STORE_PRIORITY: "aws-secrets-manager,kubernetes-secrets"
```

## Next Steps

- Read [DEVELOPER_GUIDE.md](./DEVELOPER_GUIDE.md) for detailed usage examples
- See [ARCHITECTURE.md](./ARCHITECTURE.md) for architecture details
- Check [DEPLOYMENT.md](./DEPLOYMENT.md) for production deployment guidance


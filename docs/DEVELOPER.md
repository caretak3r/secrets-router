# Developer Guide

Quick guide for developers consuming secrets from the Secrets Router service.

**Prerequisites**: Secrets Router and DAPR are already installed on your cluster.

## Create Your Secrets

Create Kubernetes secrets in the same namespace where your application will run:

```bash
# Create namespace for your application
kubectl create namespace my-app

# Create secrets
kubectl create secret generic db-credentials \
  --from-literal=host=postgres.example.com \
  --from-literal=username=admin \
  --from-literal=password=secretpassword \
  -n my-app

kubectl create secret generic api-keys \
  --from-literal=stripe-key=sk_test_12345 \
  --from-literal=jwt-secret=your-jwt-secret \
  -n my-app

# Verify secrets
kubectl get secrets -n my-app
```

## Configure Your Service

In your Helm chart's `values.yaml`, map the secrets your service needs:

```yaml
your-service:
  enabled: true
  secrets:
    db-credentials: "db-credentials"    # Must match secret name in Kubernetes
    api-keys: "api-keys"               # Must match secret name in Kubernetes
```

**Important**: The secret name in your code must match the key in the `secrets` map above.

## Access Secrets in Your Code

Your service receives these environment variables automatically:
- `SECRETS_ROUTER_URL`: URL for accessing secrets
- `TEST_NAMESPACE`: Namespace where secrets are stored

### Python Example

```python
import os
import requests

def get_secret(secret_name: str, secret_key: str) -> str:
    url = f"{os.getenv('SECRETS_ROUTER_URL')}/secrets/{secret_name}/{secret_key}"
    response = requests.get(url, params={"namespace": os.getenv("TEST_NAMESPACE")})
    return response.json()["value"]

# Usage
db_host = get_secret("db-credentials", "host")
db_password = get_secret("db-credentials", "password")
stripe_key = get_secret("api-keys", "stripe-key")
```

### Node.js Example

```javascript
const http = require('http');

function getSecret(secretName, secretKey) {
    return new Promise((resolve, reject) => {
        const url = `${process.env.SECRETS_ROUTER_URL}/secrets/${secretName}/${secretKey}`;
        const req = http.get(`${url}?namespace=${process.env.TEST_NAMESPACE}`, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => resolve(JSON.parse(data).value));
        });
        req.on('error', reject);
    });
}

// Usage
async function main() {
    const dbHost = await getSecret("db-credentials", "host");
    const dbPassword = await getSecret("db-credentials", "password");
    const stripeKey = await getSecret("api-keys", "stripe-key");
    
    console.log(`DB Host: ${dbHost}`);
}
```

### Go Example

```go
package main

import (
    "encoding/json"
    "fmt"
    "io"
    "net/http"
    "os"
)

type SecretResponse struct {
    Value string `json:"value"`
}

func getSecret(secretName, secretKey string) (string, error) {
    routerURL := os.Getenv("SECRETS_ROUTER_URL")
    namespace := os.Getenv("TEST_NAMESPACE")
    
    url := fmt.Sprintf("%s/secrets/%s/%s?namespace=%s", 
        routerURL, secretName, secretKey, namespace)
    
    resp, err := http.Get(url)
    if err != nil {
        return "", err
    }
    defer resp.Body.Close()
    
    body, err := io.ReadAll(resp.Body)
    if err != nil {
        return "", err
    }
    
    var secretResp SecretResponse
    if err := json.Unmarshal(body, &secretResp); err != nil {
        return "", err
    }
    
    return secretResp.Value, nil
}

func main() {
    dbHost, err := getSecret("db-credentials", "host")
    if err != nil {
        panic(err)
    }
    
    dbPassword, err := getSecret("db-credentials", "password")
    if err != nil {
        panic(err)
    }
    
    fmt.Printf("DB Host: %s\n", dbHost)
}
```

## API Endpoint

```
GET /secrets/{secret_name}/{secret_key}?namespace={namespace}
```

**Response:**
```json
{
  "backend": "kubernetes-secrets",
  "secret_name": "db-credentials", 
  "secret_key": "password",
  "value": "secretpassword"
}
```

## Troubleshooting Secret Access

Test if your secrets are accessible:

```bash
# Test from any pod in the same namespace
kubectl exec -it <your-pod> -n my-app -- \
  curl "http://secrets-router:8080/secrets/db-credentials/password?namespace=my-app"

# Check if secret exists
kubectl get secret db-credentials -n my-app

# Check secrets-router logs
kubectl logs -n dapr-control-plane -l app.kubernetes.io/name=secrets-router
```

If you get a 404 error:
1. Verify the secret exists in the correct namespace
2. Check that the secret name in your code matches the configuration
3. Ensure your pod is in the same namespace as the secret

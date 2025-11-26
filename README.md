# Kubernetes Secrets Broker

A Dapr-based secrets broker service that provides a simple HTTP API for applications to fetch secrets from Kubernetes Secrets and AWS Secrets Manager.

## Overview

The Secrets Broker is deployed as an **umbrella Helm chart** that includes:
- **Dapr Control Plane**: Provides mTLS and component abstraction
- **Secrets Router Service**: HTTP API service for fetching secrets
- **Dapr Components**: Kubernetes Secrets and AWS Secrets Manager integrations

## Key Features

- ✅ **Namespace-Scoped**: All secrets are namespace-scoped (no cluster-wide secrets)
- ✅ **Auto-Decoding**: Kubernetes secrets automatically decoded (base64 → plain text)
- ✅ **Priority Resolution**: Tries Kubernetes Secrets first, then AWS Secrets Manager
- ✅ **Path-Based AWS**: Configurable path prefix for AWS Secrets Manager
- ✅ **Simple API**: Developer-friendly HTTP API
- ✅ **mTLS**: Automatic mTLS via Dapr Sentry
- ✅ **Umbrella Chart**: Single Helm chart installs everything

## Quick Start

### 1. Install Umbrella Chart

```bash
# Install in your namespace
helm install secrets-broker ./charts/umbrella \
  --namespace production \
  --create-namespace \
  --set global.namespace=production
```

### 2. Deploy Dapr Components

```bash
# Deploy Kubernetes Secrets component
kubectl apply -f dapr-components/kubernetes-secrets-component.yaml -n production

# Deploy AWS Secrets Manager component (if using AWS)
kubectl apply -f dapr-components/aws-secrets-manager-component.yaml -n production
```

### 3. Use in Your Application

```python
import requests

# Get secret value (always returns decoded value)
response = requests.get(
    "http://secrets-router:8080/secrets/database-credentials/password",
    params={"namespace": "production"}
)
secret_value = response.json()["value"]
```

## Architecture

```
Application → Secrets Router → Dapr Sidecar → Dapr Components → Backend Stores
```

- **Applications** make HTTP requests to Secrets Router service
- **Secrets Router** queries Dapr sidecar for secrets
- **Dapr Sidecar** routes to appropriate component (K8s or AWS)
- **Components** fetch from backend stores
- **Auto-decoding** happens transparently for K8s secrets

See [ARCHITECTURE.md](./ARCHITECTURE.md) for detailed diagrams.

## Documentation

- **[Developer Guide](./DEVELOPER_GUIDE.md)**: How to consume secrets in your applications
- **[Architecture](./ARCHITECTURE.md)**: Architecture diagrams and design decisions
- **[ADR](./ADR.md)**: Architecture Decision Record
- **[Dapr Integration](./DAPR_INTEGRATION.md)**: Dapr component integration details
- **[Deployment Guide](./DEPLOYMENT.md)**: Step-by-step deployment instructions

## API Reference

### Get Secret

```
GET /secrets/{secret_name}/{secret_key}?namespace={namespace}
```

**Parameters:**
- `secret_name` (path, required): Name of the secret
- `secret_key` (path, required): Key within the secret
- `namespace` (query, required): Kubernetes namespace where secret is stored

**Response:**
```json
{
  "backend": "kubernetes-secrets",
  "secret_name": "database-credentials",
  "secret_key": "password",
  "value": "mypassword123"
}
```

**Note**: All secret values are automatically decoded and returned as plain text. Kubernetes secrets (base64 encoded) are decoded automatically.

### Health Checks

```
GET /healthz  # Liveness probe - returns HTTP 200 if service is running
GET /readyz   # Readiness probe - returns HTTP 200 if ready to receive traffic
```

**Health Check Responses:**

`/healthz` (HTTP 200):
```json
{
  "status": "healthy",
  "service": "secrets-router",
  "version": "1.0.0"
}
```

`/readyz` (HTTP 200 when ready, HTTP 503 when not ready):

When ready (HTTP 200):
```json
{
  "status": "ready",
  "service": "secrets-router",
  "dapr_sidecar": "connected",
  "version": "1.0.0"
}
```

When not ready (HTTP 503):
```json
{
  "status": "not_ready",
  "service": "secrets-router",
  "dapr_sidecar": "disconnected",
  "error": "Cannot connect to Dapr sidecar"
}
```

The `/readyz` endpoint checks connectivity to the Dapr sidecar and returns HTTP 503 if the sidecar is not reachable or not healthy. This ensures the service only receives traffic when it can actually process requests.

## Configuration

### Umbrella Chart Values

```yaml
global:
  namespace: production  # Your application namespace

secrets-router:
  env:
    SECRET_STORE_PRIORITY: "kubernetes-secrets,aws-secrets-manager"
  # Optional: Configure AWS secret paths
  # awsSecretPaths:
  #   database-credentials: "/app/secrets/production/database-credentials"
```

### AWS IRSA Configuration

If using AWS Secrets Manager:

```yaml
secrets-router:
  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/secrets-router-role
```

## Secret Storage

### Kubernetes Secrets

- **Location**: Same namespace as your application
- **Format**: `{namespace}/{secret-name}`
- **Auto-decoding**: Yes (base64 → plain text)

### AWS Secrets Manager

- **Location**: AWS Secrets Manager
- **Format**: Full paths configured in Helm chart values, or simple names
- **Configuration**: Secret paths configured in `values.yaml` (e.g., `database-credentials: "/app/secrets/production/database-credentials"`)
- **Auto-decoding**: No (already decoded)

## Examples

See [DEVELOPER_GUIDE.md](./DEVELOPER_GUIDE.md) for code examples in:
- Python
- Go
- Node.js/TypeScript

## Project Structure

```
k8s-secrets-broker/
├── charts/
│   ├── umbrella/          # Umbrella chart (Dapr + Secrets Router)
│   ├── dapr/               # Dapr control plane chart
│   └── secrets-router/     # Secrets Router service chart
├── secrets-router/         # Python service implementation
├── dapr-components/        # Dapr component definitions
├── scripts/                # Build and deployment scripts
└── docs/                   # Documentation
```

## Building

```bash
# Build Docker image
make build

# Build and push to registry
make build-push IMAGE_REGISTRY=your-registry.io IMAGE_TAG=v1.0.0
```

## Deployment

```bash
# Install umbrella chart
helm install secrets-broker ./charts/umbrella \
  --namespace production \
  --create-namespace

# Deploy Dapr components
kubectl apply -f dapr-components/ -n production
```

## Troubleshooting

See [DEVELOPER_GUIDE.md](./DEVELOPER_GUIDE.md#troubleshooting) for troubleshooting tips.

## License

See [LICENSE](./LICENSE) file.

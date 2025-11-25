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

# Get secret value
response = requests.get(
    "http://secrets-router:8080/secrets/database-credentials/password",
    params={"namespace": "production", "decode": "true"}
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
GET /secrets/{secret_name}/{secret_key}?namespace={namespace}&decode={true|false}
```

**Parameters:**
- `secret_name` (path, required): Name of the secret
- `secret_key` (path, required): Key within the secret
- `namespace` (query, required): Kubernetes namespace where secret is stored
- `decode` (query, optional): If `true`, return decoded value; if `false` (default), return base64 encoded

**Response:**
```json
{
  "backend": "kubernetes-secrets",
  "secret_name": "database-credentials",
  "secret_key": "password",
  "value": "mypassword123",
  "encoded": false
}
```

### Health Checks

```
GET /healthz  # Liveness probe
GET /readyz   # Readiness probe
```

## Configuration

### Umbrella Chart Values

```yaml
global:
  namespace: production  # Your application namespace

secrets-router:
  env:
    SECRET_STORE_PRIORITY: "kubernetes-secrets,aws-secrets-manager"
    AWS_SECRETS_PATH_PREFIX: "/app/secrets"  # Path prefix for AWS secrets
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
- **Format**: `{AWS_SECRETS_PATH_PREFIX}/{namespace}/{secret-name}`
- **Example**: `/app/secrets/production/database-credentials`
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

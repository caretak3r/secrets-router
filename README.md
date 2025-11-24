# Kubernetes Secrets Broker - Dapr Implementation

This project implements Option 3 from the ADR: a Dapr-based secrets broker service that routes secret requests to Kubernetes Secrets and AWS Secrets Manager backends.

## Architecture

- **Dapr Control Plane**: Provides mTLS, service mesh, and component abstraction
- **Secrets Router Service**: Python service that implements Dapr Secrets API and routes to backends
- **Dapr Components**: Kubernetes Secrets and AWS Secrets Manager integrations

## Project Structure

```
k8s-secrets-broker/
├── secrets-router/          # Python service implementation
│   ├── main.py             # FastAPI service with Dapr Secrets API
│   ├── Dockerfile          # Distroless Python image
│   └── requirements.txt    # Python dependencies
├── charts/                  # Helm charts
│   ├── dapr/               # Dapr control plane chart
│   └── secrets-router/     # Secrets router service chart
├── dapr-components/         # Dapr component definitions
│   ├── kubernetes-secrets-component.yaml
│   ├── aws-secrets-manager-component.yaml
│   └── secrets-router-component.yaml
├── scripts/                 # Build and deployment scripts
│   ├── setup.sh
│   ├── build-image.sh
│   └── deploy.sh
└── Makefile                # Convenience commands
```

## Prerequisites

- Docker
- kubectl (configured with cluster access)
- Helm 3.x
- Kubernetes cluster (1.24+)

## Quick Start

### 1. Setup

```bash
make setup
```

This checks for required tools and prepares the environment.

### 2. Build Docker Image

```bash
# Build locally
make build

# Build with custom tag
make build IMAGE_TAG=v1.0.0

# Build and push to registry
make build-push IMAGE_REGISTRY=your-registry.io IMAGE_TAG=v1.0.0
```

### 3. Deploy to Kubernetes

```bash
# Deploy to default namespace
make deploy

# Deploy to custom namespace
make deploy NAMESPACE=production

# Deploy with custom image registry
make deploy IMAGE_REGISTRY=your-registry.io IMAGE_TAG=v1.0.0
```

### 4. Verify Deployment

```bash
# Check pod status
make k8s-status

# View logs
make k8s-logs

# Port forward for testing
make k8s-port-forward
```

## Manual Steps

### Build Image

```bash
./scripts/build-image.sh [tag] [registry]
```

### Deploy

```bash
./scripts/deploy.sh [namespace] [registry] [tag]
```

## Configuration

### Environment Variables

Configure via Helm values (`charts/secrets-router/values.yaml`):

- `DEBUG_MODE`: Enable debug logging
- `LOG_LEVEL`: Logging level (INFO, DEBUG, etc.)
- `K8S_CLUSTER_WIDE_NAMESPACE`: Namespace for cluster-wide secrets
- `AWS_REGION`: AWS region for Secrets Manager
- `AWS_SECRETS_MANAGER_PREFIX`: Prefix for AWS secrets
- `AWS_CLUSTER_SECRETS_PREFIX`: Prefix for cluster-wide AWS secrets

### AWS IRSA Configuration

For AWS IAM Roles for ServiceAccounts (IRSA), update `charts/secrets-router/values.yaml`:

```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT:role/secrets-router-role
```

## API Usage

### Dapr Secrets API

Applications with Dapr sidecar can use:

```bash
# Via Dapr sidecar HTTP API
curl http://localhost:3500/v1.0/secrets/secrets-router-store/my-secret

# Via Dapr SDK (Python example)
from dapr.clients import DaprClient

with DaprClient() as d:
    secret = d.get_secret(store_name="secrets-router-store", key="my-secret")
```

### Direct API

```bash
# Health check
curl http://secrets-router:8080/healthz

# Get secret
curl http://secrets-router:8080/v1/secrets/my-secret?namespace=default
```

## Secret Resolution Priority

1. **Kubernetes Secrets** (namespace-scoped)
2. **Kubernetes Secrets** (cluster-wide in `kube-system`)
3. **AWS Secrets Manager** (namespace path: `/app/secrets/{namespace}/{secret}`)
4. **AWS Secrets Manager** (cluster path: `/app/secrets/cluster/{secret}`)

## Development

### Local Development

```bash
# Install dependencies
make dev-install

# Run locally
make dev-run
```

### Testing

```bash
# Lint code
make lint

# Run tests (when implemented)
make test
```

## Troubleshooting

### Check Dapr Status

```bash
kubectl get pods -n dapr-system
kubectl logs -n dapr-system -l app=dapr-operator
```

### Check Secrets Router

```bash
kubectl get pods -n <namespace>
kubectl logs -n <namespace> -l app.kubernetes.io/name=secrets-router
kubectl describe pod -n <namespace> -l app.kubernetes.io/name=secrets-router
```

### Verify Dapr Components

```bash
kubectl get components -n <namespace>
kubectl describe component -n <namespace> <component-name>
```

## Uninstall

```bash
make k8s-uninstall NAMESPACE=<namespace>
```

Or manually:

```bash
helm uninstall secrets-router -n <namespace>
helm uninstall dapr -n dapr-system
```

## Security Considerations

- **mTLS**: Enabled by default via Dapr Sentry
- **RBAC**: ServiceAccount with minimal required permissions
- **Distroless Image**: Minimal attack surface
- **Non-root**: Container runs as non-root user (UID 65532)
- **Read-only**: Service only reads secrets, never writes

## References

- [Dapr Documentation](https://docs.dapr.io/)
- [Dapr Secrets API](https://docs.dapr.io/reference/api/secrets_api/)
- [Dapr Helm Charts](https://github.com/dapr/helm-charts)
- [ADR Document](./ADR.md)

